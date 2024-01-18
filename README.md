## Overview

This repository contains samples of usage and concepts of the Ballerina language in a walk-through style. While the samples may use standard libraries they will generally not go into detail about the standard libraries and features, but would rather focus on language features.

Latest version tested against - Ballerina 2201.8.2

### Structure

- Samples are ordered in the table below to suggest an order to be followed. However, you should generally be able to follow any arbitrary sample without having to go through the previous samples if necessary. 
- Each folder contains 
    - the sample as a Ballerina notebook 
    - the sample as an MD file (README)
    - (optionally) a separate .bal file with just the code (but this may not be a 1:1 match with the code in the notebook since the same function may be updated)
    - (optionally) diagrams corresponding to the code

    Notes about the notebook:
    - due to some known issues in the Ballerina notebook, some snippets may not run as expected, and you may have to run the code in a separate file
    - the notebook to MD format conversion is done using [a Ballerina library](https://github.com/MaryamZi/balnb_to_md)

### Samples

| Sample | Areas Covered |
| :--: | ------------- |
|   [working_with_json_response](working_with_json_response)  | JSON, query expressions, JSON to record conversion, HTTP client |
|   [working_with_xml_response](working_with_xml_response)  | XML, query expressions, HTTP client |
|   [Draft] [concurrency_safety_with_isolated](concurrency_safety_with_isolated)  | isolated, concurrency safety |
