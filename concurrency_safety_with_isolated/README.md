### Mutability


```ballerina
int[] & readonly a = [];
a[0] = 1; // cannot update 'readonly' value of type '(int[] & readonly)'
a = [1]; // OK

final int[] b = [];
b[0] = 1; // OK
b = [1]; // cannot assign a value to final 'b'

final int[] & readonly c = [];
c[0] = 1; // cannot update 'readonly' value of type '(int[] & readonly)'
c = [1]; // cannot assign a value to final 'c'
```


### Workers, async calls, strands, and threads

Quoting the [spec](https://ballerina.io/spec/lang/master/#section_7.2)

> Ballerina's concurrency model supports both threads and coroutines. A Ballerina program is executed on one or more threads. A thread may run on a separate core simultaneously with other threads, or may be pre-emptively multitasked with other threads onto a single core.

> Each thread is divided into one or more strands. No two strands belonging to the same thread can run simultaneously. Instead, all the strands belonging to a particular thread are cooperatively multitasked. Strands within the same thread thus behave as coroutines relative to each other. A strand enables cooperative multitasking by yielding. When a strand yields, the runtime scheduler may suspend execution of the strand, and switch its thread to executing another strand.

Workers are scheduled on the same thread as the parent strand, unless the workers are (inferred to be) isolated.


```ballerina
// bal run isolated.bal -- 1 2 3 4
public function main(int... ints) returns error? {
    // default-worker-init
    // ...

    worker w returns int {
        int sum = 0;
        foreach int i in ints {
            sum += i;
        }
        return sum;
    }

    future<int> startFut = start int:sum(...ints);

    future<int> workerFut = w;

    int startSum = check wait startFut;
    int workerSum = check wait workerFut;
}
```


### Why `isolated`?

With workers (on different threads) running concurrently, there could be data races (and therefore, problems), when accessing mutable state from these workers.

#### Where is this specifically a problem in Ballerina?

Two entry points in Ballerina:
- the `main` function
- services

While applicable to the `main` (or any other entry) function, main requirements for concurrency and concurrency safety are with services, when listeners call resource or remote methods of services.

E.g., how does the listener decide whether it is safe to dispatch request concurrently to remote/resource methods of the same service.


```ballerina
import ballerina/http;

enum CakeKind {
    BUTTER_CAKE = "Butter Cake",
    CHOCOLATE_CAKE = "Chocolate Cake",
    TRES_LECHES = "Tres Leches"
}

enum OrderStatus {
    PENDING = "pending",
    IN_PROGRESS = "in progress",
    COMPLETED = "completed"
}

type OrderDetail record {|
    CakeKind item;
    int quantity;
|};

type Order record {|
    string username;
    OrderDetail[] order_items;
|};

map<Order> orders = {};
map<OrderStatus> orderStatus = {};
int orderId = 1000; // just for demonstration

service on new http:Listener(8080) {
    resource function post 'order(Order newOrder) returns http:Created|http:BadRequest? {
        // ...

        string orderId = nextOrderId();

        orders[orderId] = newOrder;

        orderStatus[orderId] = PENDING;

        // ...
        return http:CREATED;
    }
}

function nextOrderId() returns string {
    int nextOrderId = orderId;
    orderId += 1;
    return nextOrderId.toString();
}
```


`isolated` and related concepts are Ballerina's attempt at ensuring compile-time guaranteed concurrency safety.

Helps identify which functions/methods can safely be called concurrently.


### Isolated functions

A function that is safe to be called concurrently, as long as the caller can guarantee that the arguments are safe.

Argument safety:
- If the parameters allow only immutable valuables, the arguments are inherently safe, since the values passed as arguments cannot be updated.
- Also safe if the caller can guarantee that a mutable value passed as an argument is not accessed elsewhere until the function call completes (e.g., using lock statements).


```ballerina
import ballerina/http;
 
type Order record {
    string id;
    string status;
    // ...
};

service on new http:Listener(8080) {
    resource function post r1(Order ord) {
        // Alternatively, change the param type of the resource if that's possible. 
        f1(ord.cloneReadOnly()); 
    }

    resource function post r2(Order ord) {
        f2(ord);
    }

    resource function post r3(Order & readonly ord) {
        f3(ord);
    }
}

function f1(Order & readonly ord) {
    string id = ord.id;
    // ... does not access module-level mutable state
    // Since `ord` is immutable, we know it cannot be updated here.
}

// implicitly final and the type is `map<string> & readonly`
configurable map<string> statusKeys = {
    pending: "Pending",
    in\-progress: "In Progress",
    completed: "Completed"
};

function f2(Order ord) {
    string id = ord.id;
    // Safe as long as the caller guarantees exclusive access to `ord`
    // until this function completes.
    // Accessing `statusKeys` is OK since it is implictly final and immutable.
    ord.status = statusKeys.get("in-progress");
    // ... does not access module-level mutable state
}

map<Order> orderMap = {};

function f3(Order & readonly ord) {
    orderMap[ord.id.toString()] = ord;
    // Although the arguments are safe, the function accesses a mutable
    // module-level variable, which is not safe.
}
```



Note how the first two resources are identified as `isolated`, but the third resource is not, resulting in the following hint.

```bash
concurrent calls will not be made to this method since the method is not an 'isolated' method
```

As seen in the code, the third resource accesses shared mutable state in an unsafe manner (e.g., without using locks), and it is not safe to call this method concurrently. Accordingly, this results in the resource being identified as a non-`isolated` method.

While we've relied on `isolated` inference here, explicitly adding the `isolated` qualifier to the function will
- log diagnostics to convey why a function is not `isolated`
- guarantee that any future change guarantees that the function continues to be safe to be called concurrently (unless of course the author removes isolated :))

An `isolated` function defines several requirements, including 
- an `isolated` function can only call other functions/methods if they too are `isolated`
- restrictions on accessing module-level variables
- restrictions on async calls from within such functions

Also see the [spec]( https://ballerina.io/spec/lang/master/#isolated_functions).

Let's mark some of the constructs as `isolated` explicitly and check the errors.


```ballerina
import ballerina/http;

type Order record {
    string id;
    string status;
    // ...
};

service on new http:Listener(8080) {
    isolated resource function post r1(Order ord) {
        // Alternatively, change the param type of the resource if that's possible. 
        f1(ord.cloneReadOnly()); 
    }

    isolated resource function post r2(Order ord) {
        f2(ord); // invalid invocation of a non-isolated function in an 'isolated' function
                 // While `f2` can be inferred to be `isolated`, that is not enough here.
                 // has to be isolated explicitly.   
    }

    isolated resource function post r3(Order & readonly ord) {
        f3(ord);
    }
}

isolated function f1(Order & readonly ord) {
    string id = ord.id;
    // ... does not access module-level mutable state
    // Since `ord` is immutable, we know it cannot be updated here.
}

// implicitly final and the type is `map<string> & readonly`
configurable map<string> statusKeys = {
    pending: "Pending",
    in\-progress: "In Progress",
    completed: "Completed"
};

function f2(Order ord) {
    string id = ord.id;
    // Safe as long as the caller guarantees exclusive access to `ord`
    // until this function completes.
    // Accessing `statusKeys` is OK since it is implictly final and immutable.
    ord.status = statusKeys.get("in-progress");
    // ... does not access module-level mutable state
}

map<Order> orderMap = {};

isolated function f3(Order & readonly ord) {
    orderMap[ord.id.toString()] = ord; // invalid access of mutable storage in an 'isolated' function
    // Although the arguments are safe, the function accesses a mutable
    // module-level variable, which is not safe.
}
```


An `isolated` function is, therefore, a function that works with mutable state without restrictions only if the mutable state was passed as arguments.

**Note**: just because a function is `isolated`, doesn't mean it is safe to call concurrently. Safety depends on the arguments also. And as we will see later, for objects (and therefore, services) depends on the object too.


### Isolated variables

But, there may be valid requirements to access shared mutable state in a safe manner (e.g., appropriately using lock statements).


```ballerina
import ballerina/http;
 
type Order record {
    string id;
    string status;
    // ...
};

service on new http:Listener(8080) {
    resource function post r3(Order & readonly ord) {
        f3(ord);
    }
}

map<Order> orderMap = {};

function f3(Order & readonly ord) {
    lock {
        orderMap[ord.id.toString()] = ord;
        // OK now, since any and all access of `orderMap` happens within a lock statement
    }
}
```


The hint goes away for the third resource also now.


#### Isolated root

As implied in the previous section, an `isolated` variable can be accessed only within a lock statement.

But, are only locks enough?


```ballerina
int[] a = [1, 2];

int[][] b = [a];

function f1() {
    lock {
        if b[0].length() == 0 {
            return;
        }
        // ...
        int x = b[0][0];
    }
}

function f2() {
    a.removeAll();
}
```


Although, lock statements are used to access the array and it's members via `b`, the mutable state may be accessed without locks via other references. 

Isolated variables avoid this using the [isolated root](https://ballerina.io/spec/lang/master/#section_5.1.3) invariant.

> A variable or value is an isolated root if its mutable state is isolated from the rest of the program's mutable state: any mutable state that is freely reachable from the isolated root is reachable from outside only through the isolated root. More precisely, if some mutable state s is freely reachable from an isolated root value r, then s is not freely reachable from a variable or value that is not reachable from r except by following a reference through r; similarly, if some mutable state s is freely reachable from an isolated root variable r, then s is not freely reachable from a value that is not reachable from r and is not freely reachable from any variable other than r.


```ballerina

int[] a = [];

int[][] b = [a];

// Neither `a` nor `b` (and values assigned to them) are isolated roots.

int[] c = [];

int[][] d = [[], [1, 2]];

int[][] e = [a.clone(), c.clone(), []];

// All of `c`, `d`, and `e` are isolated roots.
```


#### Isolated expressions

An [isolated expression](https://ballerina.io/spec/lang/master/#isolated_expressions) provides the guarantee

> that the value of the expression will be an isolated root and will not be aliased

If the static type of an expression is immutable (i.e., subtype of `readonly`) or an `isolated` object (covered later), the expression is an isolated expression, irrespective of the expression kinds, subexpressions, etc.

- `clone()` and `cloneReadOnly()` are always `isolated` since they always create new and/or immutable values
- constructor expressions (e.g., list constructor) and some other kinds of expressions are isolated if all of their subexpressions are isolated
- for other kinds of expressions, where applicable, the spec defines rules specifying when they can be isolated


#### Maintaining the isolated root invariant with `isolated` variables

In order to maintain the isolated root invariant, the compiler requires any update to an isolated variable happens via isolated expressions. This applies to any update including initialization, setting a value, retrieving a value, etc.

This is analyzed along with the lock statements used to access these variables. The lock statements are the boundaries across which transfer in and out are analyzed when special values such as isolated variables are accessed. Therefore, special rules apply in such lock statements.

Quoting the [spec](https://ballerina.io/spec/lang/master/#lock-stmt):

> - Only one such variable can occur in the lock statement.
> - A function or method can be called in the lock statement only if the type of the function is isolated.
> - Transferring values out of the lock statement is constrained: the expression following a return statement must be an isolated expression; an assignment to a variable defined outside the lock statement is allowed only if left-hand side is just a variable name and the right hand side is an isolated expression. An assignment to the restricted variable is not subject to this constraint.
> - Transferring values into the lock statement is constrained: a variable-reference-expr within the lock statement that refers to a variable or parameter defined outside the lock statement is allowed only if the variable-reference-expr occurs within an expression that is isolated. A variable-reference-expr that refers to the restricted variable is not subject to this constraint. Within a non-isolated object, self behaves like a parameter.



```ballerina
int[] a = [];
 
 // error for `a` now - invalid initial value expression: expected an isolated expression 
isolated int[][] b = [[1, 3], a, [4]];

function f1(int[] arr) {
    lock {
        // error for transferring in `arr` when accessing isolated variable `b` - 
        // invalid attempt to transfer a value into a 'lock' statement with restricted variable usage
        b.push(arr);
    }
}

function f2() returns int[] {
    lock {
        // error for transferring a value out when accessing isolated variable `b` -
        // invalid attempt to transfer out a value from a 'lock' statement with restricted variable usage: expected an isolated expression
        return b[0];
    }
}

public function main() {
    int[] x = [1, 2];
    f1(x);

    int[] y = f2();
}
```


If any of these were allowed, it would violate the isolated root invariant
- if just `a` was allowed in the list constructor initializing `b`, the same mutable value would be reachable via both `a` and `b`
- if `b.push(arr)` was allowed in `f1`, the last member of `b` would be reachable via both `b` and the variable `x` in the `main` function
- if `return b[0]` was allowed in `f2`, the first member of `b` would be reachable via both `b` and the variable `y` in the `main` function

We can fix these errors using isolated expressions appropriately.


```ballerina
int[] a = [];
 
isolated int[][] b = [[1, 3], a.clone(), [4]];

function f1(int[] arr) {
    lock {
        b.push(arr.clone());
    }
}

function f2() returns int[] {
    lock {
        return b[0].clone();
    }
}

public function main() {
    int[] x = [1, 2];
    f1(x);

    int[] y = f2();
}
```


### Isolated objects

In the previous order service snippets, we had mutable state as module-level variables. But what about object (and therefore, service) fields that are mutable? 

Similar to module-level variables, mutability depends on two things
- whether the field is `final`
- whether the type of the field is a subtype of `readonly`

Is it enough for just object methods to be `isolated`?


```ballerina
class Stacks {
    int[][] list = [];

    isolated function get(int i) returns int[] {
        return self.list[i];
    }

    isolated function put(int[] arr) {
        self.list.push(arr);
    }
}
```


**Note:** `self` can be accessed within an `isolated` method. Here, `self` is is analyzed like a parameter to the method.


While both methods are `isolated`, note how `Stacks` is not an isolated root.

- the `list` field is not immutable and is not private. `list` and it's members can be accessed in a manner that is not concurrency-safe, wherever a `Stacks` object is accessible
- retrieving and updating the mutable fields can be done in a manner than violates the isolated root invariant

Moreover, mutable fields of the object can be accessed in an unsafer manner, without locks, even when the methods are `isolated`.

Therefore, for a method call to be safe, it is not enough for just the method to be `isolated`. We need a mechanism to ensure that the object is also safe - ebter isolated objects.


To ensure that an object is an `isolated` object, an additional set of constraints apply.

- mutable (non-final and/or mutable value) fields have to be private
- when `self` is used to access a mutable field, rules similar to those applicable when accessing an `isolated` variable apply


```ballerina
isolated class Stacks {
    private int[][] list = []; // private field

    isolated function get(int i) returns int[] {
        lock { // use of locks
            return self.list[i].clone(); // use of isolated expressions to transfer in/out
        }
    }

    isolated function put(int[] arr) {
        lock {
            self.list.push(arr.clone());
        }
    }
}
```


Accordingly, if the mutable state of the order service were non-private fields of the service object, warnings will still be logged even if the methods are isolated.


```ballerina
import ballerina/http;

configurable int port = 8080;

enum CakeKind {
    BUTTER_CAKE = "Butter Cake",
    CHOCOLATE_CAKE = "Chocolate Cake",
    TRES_LECHES = "Tres Leches"
}

enum OrderStatus {
    PENDING = "pending",
    IN_PROGRESS = "in progress",
    COMPLETED = "completed"
}

type OrderDetail record {|
    CakeKind item;
    int quantity;
|};

type Order record {|
    string username;
    OrderDetail[] order_items;
|};

type OrderUpdate record {|
    OrderDetail[] order_items;
|};

service on new http:Listener(port) {
    map<Order> orders = {};
    map<OrderStatus> orderStatus = {};

    // concurrent calls will not be made to this method since the service is not an 'isolated' service
    resource function get 'order/[string orderId]() returns http:Ok|http:NotFound {
        if !self.orderStatus.hasKey(orderId) {
            return <http:NotFound>{};
        }

        return http:OK;
    }

    // concurrent calls will not be made to this method since the service is not an 'isolated' service
    resource function delete 'order/[string orderId]() returns http:Ok|http:Forbidden|http:NotFound {
        if !self.orderStatus.hasKey(orderId) {
            return <http:NotFound>{};
        }

        if self.orderStatus.get(orderId) != PENDING {
            return <http:Forbidden>{};
        }
        _ = self.orderStatus.remove(orderId);

        _ = self.orders.remove(orderId);

        return http:OK;
    }
}
```


Once we fix the object to be an isolated object, these warnings will also go away.


```ballerina
import ballerina/http;

configurable int port = 8080;

enum CakeKind {
    BUTTER_CAKE = "Butter Cake",
    CHOCOLATE_CAKE = "Chocolate Cake",
    TRES_LECHES = "Tres Leches"
}

enum OrderStatus {
    PENDING = "pending",
    IN_PROGRESS = "in progress",
    COMPLETED = "completed"
}

type OrderDetail record {|
    CakeKind item;
    int quantity;
|};

type Order record {|
    string username;
    OrderDetail[] order_items;
|};

type OrderUpdate record {|
    OrderDetail[] order_items;
|};

service on new http:Listener(port) {
    private map<Order> orders = {};
    private map<OrderStatus> orderStatus = {};

    resource function get 'order/[string orderId]() returns http:Ok|http:NotFound {
        lock {
            if !self.orderStatus.hasKey(orderId) {
                return <http:NotFound>{};
            }
        }

        return http:OK;
    }

    resource function delete 'order/[string orderId]() returns http:Ok|http:Forbidden|http:NotFound {
        lock {
            if !self.orderStatus.hasKey(orderId) {
                return <http:NotFound>{};
            }

            if self.orderStatus.get(orderId) != PENDING {
                return <http:Forbidden>{};
            }
            
            _ = self.orderStatus.remove(orderId);
        }


        lock {
            _ = self.orders.remove(orderId);
        }

        return http:OK;
    }
}
```


Based on this analysis of both objects and methods, a listener can identify when and if it is safe to call a service remote or resource method concurrently, as long as the listener can guarantee exclusive access to the mutable arguments, if applicable.


#### Using `isolated` objects within `isolated` functions

With module-level state that is `final` but not immutable, we previously saw how we needed to use lock statements when accessing such variables in `isolated` functions.

But what about a `final` variable that holds an `isolated` object? Since the `isolated` object guarantees that any mutable state is accessed within a lock statement, we do not have to use locks when using such a variable within an isolated function.


```ballerina
isolated class Stacks {
    private int[][] list = [];

    isolated function get(int i) returns int[] {
        lock {
            return self.list[i].clone();
        }
    }

    isolated function put(int[] arr) {
        lock {
            self.list.push(arr.clone());
        }
    }
}

Stacks s1 = new; // neither final nor an isolated variable

isolated Stacks s2 = new; // isolated variable

final Stacks s3 = new; // final

isolated function fn() {
    _ = s1.get(0); // error: invalid access of mutable storage in an 'isolated' function

    _ = s2.get(0); // error: invalid access of an 'isolated' variable outside a 'lock' statement

    lock {
        _ = s2.get(0); // OK, because `s2` is an isolated variable, and access is within a lock.
    }

    _ = s3.get(0); // OK, because `s3` is a `final` variable of an isolated object type
}
```


### Workers and async calls within `isolated` functions

There also may be scenarios where we want to have workers or do async calls within an `isolated` function (and have the strands run on separate thread). In order to allow this, we need to ensure that whatever mutable access that happens within these constructs happens safely.

For workers, this means that the worker body should meet the requirements for an `isolated` function and that captired variables are final and have a static type that is a subtype of `readonly|isolated object {}`.


```ballerina
import ballerina/io;

int[] x = [];
final int[] & readonly y = [];

public isolated function main() {
    io:println(x); // error
    io:println(y); // OK

    int[] localX = [];
    final int[] & readonly localY = [];

    // Similarly
    worker w {
        io:println(x); // error
        io:println(y); // OK

        io:println(localX); // error
        io:println(localY); // OK
    }
}
```


For an aync call (`start` action), this requires the function to be `isolated` and any argument to the function to be an isolated root. That way we can ensure mutable state isn't accessed concurrently by these strands.


```ballerina
type Config record {

};

public isolated function main() {
    Config config = {};
    string[] urls = [];

    foreach string  url in urls {
        future<string> fr = start getResult(url, config.clone());
    }

    // or
    final readonly & Config immutableConfig = config.cloneReadOnly();
    foreach string  url in urls {
        future<string> fr = start getResult(url, immutableConfig);
    }
}

isolated function getResult(string url, Config config) returns string {
    // 
    return "";
}

```


Such strands can safely scheduled on different threads.


### Inferring isolated

End users are generally not expected to explicitly add `isolated`. If the written code is safe (i.e., no compilation errors if `isolated` was added explicitly), the compiler will infer `isolated`.

Library developers, on the other hand, and others who develop publicly exposed constructs are expected to explicitly add `isolated` to guarantee `isolated`, which will eventually lead to inferring `isolated` for user code.
