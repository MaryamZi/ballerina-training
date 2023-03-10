In this sample, we will be looking at working with XML in Ballerina. We will use the HTTP client to retrieve population data via the [World Bank Indicators API](https://datahelpdesk.worldbank.org/knowledgebase/articles/889392-about-the-indicators-api-documentation) and then process the retrieved data.


This sample demonstrates the following.
- Using an HTTP client to retrieve XML data
- Query expressions
- XML subtypes and attributes
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


Let's retrieve the data for the country in XML format and write it to a file to examine the data.


```ballerina
function retrieveData(string country) returns error? {
    xml payload = check worldBankClient->get(string `/country/${country}/indicator/SP.POP.TOTL`);
    check io:fileWriteXml("all.xml", payload);
}
```


Notes:
- `country` is used as an interpolation in the string template expression that is the argument to `get`. See [string template expressions](https://ballerina.io/learn/by-example/backtick-templates/).
- the `get` remote method uses the contextually-expected type (`xml` from the left-hand side here) to try and bind the retrieved payload to the specific type. If the attempt to convert/parse as the specific type fails, an error will be returned. See [API docs for the HTTP client's `get` method](https://lib.ballerina.io/ballerina/http/latest/clients/Client#get) and [dependently-typed functions](https://ballerina.io/learn/by-example/dependent-types/).
- `remote` and `resource` methods indicate network interactions. Such methods have to be called using the `->` syntax. This differentiates between network calls and normal function/method calls.
- The `get` method and the `io:fileWriteXml` function may return an error value at runtime. Using `check` with an expression that may evaluate to an error results in the error being returned immediately if the expression evaluates to an error at runtime. See [`check` expression](https://ballerina.io/learn/by-example/check-expression/). 


```ballerina
public function main() returns error? {
    check retrieveData("LK");
}
```


Examining the content written to the file, we can observe that the XML document has separate XML elements representing population data for each year. The elements are named `wb:data` where `wb` is the namespace "http://www.worldbank.org".


Now that we know the structure of the payload, let's update the `retrieveData` function to retrieve the XML elements and iterate through them to collect population data at the end of each decade.


```ballerina
function retrieveData(string country) returns error? {
    xml payload = check worldBankClient->get(string `/country/${country}/indicator/SP.POP.TOTL`);

    xmlns "http://www.worldbank.org" as wb;

    xml<xml:Element> populationEveryDecade = from xml:Element population in payload/<wb:data>
                                                let xml date = population/<wb:date>,
                                                    string yearStr = date.data(),
                                                    int year = check int:fromString(yearStr)
                                                where year % 10 == 0
                                                select population;
            
    check io:fileWriteXml("population_every_decade.xml", 
                          xml `<wb:data xmlns:wb="http://www.worldbank.org">${populationEveryDecade}</wb:data>`);
}
```


Notes:
- `xml:Element` is a builtin subtype of `xml` defined in the [`lang.xml` lang library](https://lib.ballerina.io/ballerina/lang.xml/0.0.0) to represent XML element items. Other builtin `xml` subtypes are `xml:Comment`, `xml:ProcessingInstruction`, and `xml:Text`.
- a [query expression](https://ballerina.io/learn/by-example/#query-expressions) is used to create a sequence of XML elements with just the information from the years (end of a decade) we are interested in
    - a [`let` clause](https://ballerina.io/learn/by-example/let-clause/) in a query expression allows declaring temporary variables that will be visible in the rest of the query expression
    - a `where` clause can be used to filter based on the (boolean) result of an expression
    - a `select` clause specifies the value to include. In this example we select the entire population XML element as is.
- an `xmlns` statement is used to declare the `wb` XML namespace. Subsequent code can then use this namespace prefix. Also see [XML namespaces](https://ballerina.io/learn/by-example/xml-namespaces/) and [XMLNS declarations](https://ballerina.io/learn/by-example/xmlns-declarations/).
- XML navigation in the form of `a/<b>` retrieves for every element `e` in `a`, every element named `b` in the children of `e`. Ballerina provides comprehensive support for XML navigation, see [XML navigation](https://ballerina.io/learn/by-example/xml-navigation/).


Examining the data written to `population_every_decade.xml` now, we can see that it consists of only the filtered data.


Let's now extract out just the population against the year at the end of each decade. Let's use a query expression to add this information to an in-memory map instead of writing it to a file.


```ballerina
function retrieveData(string country) returns map<int>|error {
    xml payload = check worldBankClient->get(string `/country/${country}/indicator/SP.POP.TOTL`);

    xmlns "http://www.worldbank.org" as wb;

    return map from xml:Element population in payload/<wb:data>
                let xml date = population/<wb:date>,
                    string yearStr = date.data(),
                    int year = check int:fromString(yearStr)
                where year % 10 == 0
                select [yearStr, check int:fromString((population/<wb:value>).data())];
}
```


Notes:
- the return type of the function has been changed to to allow returning a map of integers now
- in order to create a map with a query expression, the `map` keyword needs to be used before the `from` keyword. The first expression in the list constructor in the `select` clause is used as the key and the second expression is used as the value. Also see [Creating maps with query expressions](https://ballerina.io/learn/by-example/create-maps-with-query/).


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


Ballerina also supports convenient syntax to access attributes of XML elements. For example, an attribute that is expected to always be present can be accessed using the `a.b` syntax. An optional attribute can be accessed using `a?.b`, and unlike with required attribute access which returns an error if the attribute is not present, optional attribute access will return nil. Also see [XML access](https://ballerina.io/learn/by-example/xml-access/).

All of the attributes of an XML element can also be accessed using the [`getAttributes()` function](https://lib.ballerina.io/ballerina/lang.xml/0.0.0/functions#getAttributes) defined in the XML lang library. The attributes are returned as a map of strings. Also see the [API documentation for the XML lang library](https://lib.ballerina.io/ballerina/lang.xml/0.0.0) for other functions available for XML.


```ballerina
xml:Element payload = check worldBankClient->get(string `/country/LK/indicator/SP.POP.TOTL`);

string lastUpdated = check payload.lastupdated;
io:println("Last Updated: ", lastUpdated);

map<string> attributes = payload.getAttributes();
io:println("All attributes: ", attributes);
```


Output would look similar to

```cmd
Last Updated: 2022-12-22
All attributes: {"{http://www.w3.org/2000/xmlns/}wb":"http://www.worldbank.org","page":"1","pages":"2","per_page":"50","total":"62","sourceid":"2","sourcename":"World Development Indicators","lastupdated":"2022-12-22"}
```


**Working with user-defined types**

As we saw in the previous sample, JSON to user-defined application-specific types is straightforward due to the natural mapping from JSON objects and arrays to Ballerina mappings and lists.

But, for XML, there is no such direct mapping and therefore, the language does not define a direct XML to record conversion. 

However, depending on the use-case, you could use the [`xmldata:fromXml` function](https://lib.ballerina.io/ballerina/xmldata/2.3.1/functions#fromXml) in the `ballerina/xmldata` standard library module for conversion from XML to record.


Let's first define a record named `PopulationByYear`that maps to each population XML item.

The field names have to be an exact match with those expected in the payload (including the namespace prefix). `\` can be used to include non-identifier characters (e.g., `:`) in names of fields. Also see [identifiers](https://ballerina.io/learn/by-example/identifiers/).


```ballerina
type PopulationByYear record {|
    string wb\:indicator;
    string wb\:country;
    string wb\:countryiso3code;
    string wb\:date;
    int wb\:value;
    string wb\:unit;
    string wb\:obs_status;
    int wb\:decimal;
|};
```


We can now use this type to convert the retrieved XML payload.


```ballerina
function retrieveData(string country) returns map<int>|error {
    xml payload = check worldBankClient->get(string `/country/${country}/indicator/SP.POP.TOTL`);

    record {|
        PopulationByYear[] wb\:data;
    |} rec = check xmldata:fromXml(payload/*);

    return map from PopulationByYear population in rec.wb\:data
                    let string yearStr = population.wb\:date,
                        int year = check int:fromString(yearStr)
                    where year % 10 == 0
                    select [yearStr, population.wb\:value];
}
```


XML navigation in the form of `payload/*` results in the children of `e`, for every element `e` in `payload`.


