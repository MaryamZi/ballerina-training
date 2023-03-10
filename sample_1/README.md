In this sample, we will be looking at some key features of Ballerina using the HTTP client to retrieve population data via the [World Bank Indicators API](https://datahelpdesk.worldbank.org/knowledgebase/articles/889392-about-the-indicators-api-documentation) and then processing the retrieved data.


This sample demonstrates the following.
- Using an HTTP client to retrieve JSON data
- Working directly with the JSON payload
- Query expressions
- Defining and using application-specific types corresponding to JSON payload


Let's first import the required modules. 


```ballerina
import ballerina/http;
import ballerina/io;
```


Let's now implement the logic step by step.


Let's initialize an `http:Client` object specifying the URL for the World Bank API. Note that we have had to pass 1.1 as the HTTP version, since the Ballerina HTTP client defaults to 2.0 as the version, but the backend doesn't support the same.


```ballerina
final http:Client worldBankClient = check new ("http://api.worldbank.org/v2", httpVersion = http:HTTP_1_1);
```


Let's assume we have a parameter named `country` that holds the country code for the data we are interested in. This can also be a variable (local, configurable, module-level, etc.) or even a constant.


Let's retrieve the data for the country in JSON format and write it to a file to examine the data.


```ballerina
function retrieveData(string country) returns error? {
    json payload = check worldBankClient->get(string `/country/${country}/indicator/SP.POP.TOTL?format=json`);
    check io:fileWriteJson("all.json", payload);
}
```


Notes:
- `country` is used as an interpolation in the string template expression that is the argument to `get`. See [string template expressions](https://ballerina.io/learn/by-example/backtick-templates/).
- the `get` remote method uses the contextually-expected type (`json` from the left-hand side here) to try and bind the retrieved payload to the specific type. If the attempt to convert/parse as the specific type fails, an error will be returned. See [API docs for the HTTP client's `get` method](https://lib.ballerina.io/ballerina/http/latest/clients/Client#get) and [dependently-typed functions](https://ballerina.io/learn/by-example/dependent-types/).
- `remote` and `resource` methods indicate network interactions. Such methods have to be called using the `->` syntax. This differentiates between network calls and normal function/method calls.
- The `get` method and the `io:fileWriteJson` function may return an error value at runtime. Using `check` with an expression that may evaluate to an error results in the error being returned immediately if the expression evaluates to an error at runtime. See [`check` expression](https://ballerina.io/learn/by-example/check-expression/). 


```ballerina
public function main() returns error? {
    check retrieveData("LK");
}
```


Examining the content written to the file, we can observe the following.
- the JSON payload is a JSON array of two items
- the first item is a JSON object with information about the data (e.g., pagination, last updated, etc.)
- the second item is another array of JSON objects where each object contains population data for a particular year


### Working directly with JSON

Now that we know the structure of the payload, let's update the `retrieveData` function to do the following.
- retrieve the payload as a JSON array by changing the expected type (type of `payload`) to `json[]`.
- once we have the array, access the second member of the array (population data by year) and ensure its type is `json[]` (in line with what we observed when examining the payload)
- then iterate through that array and collect population data at the end of each decade


```ballerina
function retrieveData(string country) returns error? {
    json[] payload = check worldBankClient->get(string `/country/${country}/indicator/SP.POP.TOTL?format=json`);
    
    json[] populationByYear = check payload[1].ensureType();

    json[] populationEveryDecade = from json population in populationByYear
                                        let string yearStr = check population.date,
                                            int year = check int:fromString(yearStr)
                                   where year % 10 == 0
                                   select population;
                                   
    check io:fileWriteJson("population_every_decade.json", populationEveryDecade);
}
```


Notes:
- [`value:ensureType`](https://lib.ballerina.io/ballerina/lang.value/0.0.0/functions#ensureType) works similar to a cast, but returns an error instead of  panicking if the value does not belong to the target type. It is also a dependently-typed function and infers the `typedesc` to ensure against from the expected type (`json[]` here) if not explicitly specified.
- when `check` is used with JSON access and the expected type is a subtype of `()|boolean|int|float|decimal|string`, it is equivalent to using `value:ensureType` with the JSON access. For example, `string yearStr = check population.date` is equivalent to `string yearStr = check value:ensureType(population.date)`.

  See
    - https://ballerina.io/learn/by-example/access-json-elements
    - https://medium.com/ballerina-techblog/ballerinas-json-type-and-lax-static-typing-3b952f6add01 
    - https://medium.com/ballerina-techblog/ballerina-working-with-json-part-i-json-to-record-conversion-1e810b0a30f0 
    
- a [query expression](https://ballerina.io/learn/by-example/#query-expressions) is used to create a JSON array with just the information from the years (end of a decade) we are interested in
    - a [`let` clause](https://ballerina.io/learn/by-example/let-clause/) in a query expression allows declaring temporary variables that will be visible in the rest of the query expression
    - a `where` clause can be used to filter based on the (boolean) result of an expression
    - a `select` clause specifies the value to include. In this example we select the entire population JSON object as is.


Examining the data written to `population_every_decade.json` now, we can see that it consists of only the filtered data.


Let's now extract out just the population against the year at the end of each decade. Let's use a query expression to add this information to an in-memory map instead of writing it to a file.


```ballerina
function retrieveData(string country) returns map<int>|error {
    json[] payload = check worldBankClient->get(string `/country/${country}/indicator/SP.POP.TOTL?format=json`);
    
    json[] populationByYear = check payload[1].ensureType();

    return map from json population in populationByYear
                let string yearStr = check population.date,
                    int year = check int:fromString(yearStr)
                where year % 10 == 0
                select [yearStr, check population.value];
}
```


Notes:
- the return type of the function has been changed to to allow returning a map of integers now
- in order to create a map with a query expression, the `map` keyword needs to be used before the `from` keyword. The first expression in the list constructor in the `select` clause is used as the key and the second expression is used as the value. Also see [Creating maps with query expressions](https://ballerina.io/learn/by-example/create-maps-with-query/).
- the compiler uses `int` (from the return type) as the expected type for `check population.value`, which allows us to use the previously discussed convenient way of accessing JSON members and asserting the type


Printing the result returned from this function call, we can now examine the data in the map.


```ballerina
public function main() returns error? {
    map<int> populationByDecade = check retrieveData("LK");
    io:println(populationByDecade);
}
```


Output would look similar to

```cmd
{"2020":21919000,"2010":20261738,"2000":18777606,"1990":17325769,"1980":15035840}
```


The [sequence diagram](https://ballerina.io/why-ballerina/graphical/) generated for this function is the following.

![sequence diagram for retrieveData](working_with_json.png)


### Working with user-defined types

In the previous section, we looked at how we can extract the JSON payload and work directly with the JSON values.

Alternatively, we can also convert the payload to specific user-defined types and work with them instead.

To recap, the payload we received was a list of two members, where the first member was a JSON object with information about the data and the second member was another array of JSON objects containing population data for each year.

We can model user-defined types for this as follows.
- since the members of the entire payload JSON array are of two different structures (JSON object and array of JSON objects), we can use a [tuple](https://ballerina.io/learn/by-example/tuples/) to define this structure. Let's call it `PopulationIndicator`. Also see [lists in Ballerina](https://ballerina.io/learn/by-example/#lists).
- since the first member (information) is a JSON object, we can define a [record](https://ballerina.io/learn/by-example/records/) to represent the structure. Let's call it `IndicatorInfo`. Also see [mappings](https://ballerina.io/learn/by-example/#mappings) and [records](https://ballerina.io/learn/by-example/#records).
- similarly, we can define a record to represent each JSON object that contains population information. Let's call it `PopulationByYear`. Since the second member of the payload JSON array is a list of these JSON objects (same type), we can use an array of this record type (`PopulationByYear[]`) as the second member of the tuple.


Let's first define the `IndicatorInfo` and `PopulationByYear` records. 

Note how we are using the exact expected types as the types of the fields in the record (as opposed to `json`). The field names have to be an exact match with those expected in the payload. A [quoted identifier](https://ballerina.io/learn/by-example/identifiers/) (`'decimal`) is used to use a reserved keyword (`decimal`) as the name of a field.


```ballerina
type IndicatorInfo record {|
    int page;
    int pages;
    int per_page;
    int total;
    string sourceid;
    string sourcename;
    string lastupdated;
|};

type PopulationByYear record {|
    record {|
        string id;
        string value;
    |} indicator;
    record {|
        string id;
        string value;
    |} country;
    string countryiso3code;
    string date;
    int value;
    string unit;
    string obs_status;
    int 'decimal;
|};
```


We can now define `PopulationIndicator` using these records.


```ballerina
type PopulationIndicator [IndicatorInfo, PopulationByYear[]];
```


We can now use this type directly when calling the `get` method. The HTTP client will retrieve the JSON payload and attempt the conversion to `PopulationIndicator` itself. In case the conversion fails the `get` method will return an error. 


```ballerina
function retrieveData(string country) returns map<int>|error {
    PopulationIndicator payload = check worldBankClient->get(string `/country/${country}/indicator/SP.POP.TOTL?format=json`);
    
    return map from PopulationByYear population in payload[1]
                let string yearStr = population.date,
                    int year = check int:fromString(yearStr)
                where year % 10 == 0
                select [yearStr, population.value];
}
```


Note how this simplified the rest of the code too.
- we no longer have to use `value:ensureType` to retrieve the second member as an array, since the conversion is done to an array of `PopulationByYear` already
- we no longer have to use check when accessing the `date` and `value` fields since the record conversion also handled the type validation (`string` an `int` respectively)

> HTTP data binding uses the [`value:cloneWithType` lang library function](https://lib.ballerina.io/ballerina/lang.value/0.0.0/functions#cloneWithType) internally, which we could also use directly for conversion.


In the mapping above we've specified each field explicitly. Alternatively, we could also leverage [open records](https://ballerina.io/learn/by-example/open-records/) and [controlling openness](https://ballerina.io/learn/by-example/controlling-openness/) to explicitly specify only the fields we are interested in.

For example, we can explicitly specify only the `date` and `value` fields in `PopulationByYear`, since they are the only fields we are intersted in. As for the rest of the fields, we use the `json` type in the record rest descriptor to just say the rest of the fields have to be/are `json` values. Similarly, since we are not interested in the first member of the payload JSON array, we can avoid specifying a separate type for it.


```ballerina
type PopulationByYear record {|
    string date;
    int value;
    json...;
|};

type PopulationIndicator [json, PopulationByYear[]];
```


Defining user-defined (application-specific) types to represent JSON payload has numerous benefits, including
- validating the payload (structure and types) in one go
- compile-time validation of field/member access
- better tooling experience (e.g., completion, code actions)

However, conversion is a somewhat expensive operation, and if you are not interested in all the data or are interested only in a limited number of members (compared to the total number of members), direct access may be a better approach.


#### Generating user-defined types

While these records could be defined by manually, you could use the [Paste JSON as Record](https://wso2.com/ballerina/vscode/docs/edit-the-code/commands/) VSCode command to generate the initial records and update/refine if/as necessary. This way we wouldn't have to manually define each field/record.


#### Using binding patterns


Ballerina suppports binding patterns which allow extracting separate parts of a structured value to separate variables in one go. Binding patterns are quite powerful and can be used in various constructs including variable declarations, `foreach` statements, the `from` clause in query expressions/actions, `match` statements, etc.

See the [examples on binding patterns](https://ballerina.io/learn/by-example/#binding-patterns) for more details.


In the query expression in the `retrieveData` function, we only need to access the `date` and `value` fields from each `PopulationByYear` record. We can use a mapping binding pattern with just those fields to extract and assign them to two variables in the `from` clause itself.


```ballerina
function retrieveData(string country) returns map<int>|error {
    PopulationIndicator payload = check worldBankClient->get(string `/country/${country}/indicator/SP.POP.TOTL?format=json`);
    
    return map from PopulationByYear {date: yearStr, value} in payload[1]
                let int year = check int:fromString(yearStr)
                where year % 10 == 0
                select [yearStr, value];
}
```


Notes:
- `date: yearStr` here results in the value of the `date` field being assigned to a variable name `yearStr`. 
- Having just `value` is equivalent to `value: value` in the binding pattern.
- The types of the newly created variables are decided based on the `PopulationByYear` record here. Alternatively, if `var` is used, the types are inferred from the value.
- The member binding patterns can also be other structured binding patterns.

    ```ballerina
    var {country: {id, value}} = populationByYear
    ```


