import ballerina/http;
import ballerina/io;
import ballerina/xmldata;

final http:Client worldBankClient = check new ("http://api.worldbank.org/v2", httpVersion = http:HTTP_1_1);

function retrieveDataXml(string country) returns map<int>|error {
    xml payload = check worldBankClient->get(string `/country/${country}/indicator/SP.POP.TOTL`);

    xmlns "http://www.worldbank.org" as wb;

    return map from xml:Element population in payload/<wb:data>
                let xml date = population/<wb:date>,
                    string yearStr = date.data(),
                    int year = check int:fromString(yearStr)
                where year % 10 == 0
                select [yearStr, check int:fromString((population/<wb:value>).data())];
}

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

function retrieveDataApplicationSpecific(string country) returns map<int>|error {
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

function retrieveAttributes() returns error? {
    xml:Element payload = check worldBankClient->get(string `/country/LK/indicator/SP.POP.TOTL`);

    string lastUpdated = check payload.lastupdated;
    io:println("Last Updated: ", lastUpdated);

    map<string> attributes = payload.getAttributes();
    io:println("All attributes: ", attributes);
}
