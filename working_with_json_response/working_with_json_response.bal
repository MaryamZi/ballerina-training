import ballerina/http;

final http:Client worldBankClient = check new ("http://api.worldbank.org/v2", httpVersion = http:HTTP_1_1);

function retrieveDataJson(string country) returns map<int>|error {
    json[] payload = check worldBankClient->get(string `/country/${country}/indicator/SP.POP.TOTL?format=json`);
    
    json[] populationByYear = check payload[1].ensureType();

    return map from json population in populationByYear
                let string yearStr = check population.date,
                    int year = check int:fromString(yearStr)
                where year % 10 == 0
                select [yearStr, check population.value];
}

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

type PopulationIndicator [IndicatorInfo, PopulationByYear[]];

function retrieveDataApplicationSpecific(string country) returns map<int>|error {
    PopulationIndicator payload = check worldBankClient->get(string `/country/${country}/indicator/SP.POP.TOTL?format=json`);
    
    return map from PopulationByYear population in payload[1]
                let string yearStr = population.date,
                    int year = check int:fromString(yearStr)
                where year % 10 == 0
                select [yearStr, population.value];
}
