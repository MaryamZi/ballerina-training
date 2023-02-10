## Overview

This repository contains samples of usage of the Ballerina language in a walk-through style. While the samples may use standard libraries they will not go into detail about the standard libraries and features, but would rather focus on language features.

Latest tested Ballerina version - 2201.3.2

### Structure

- Samples are grouped in folders named numerically to suggest an order to be followed. However, you should be able to follow any arbitrary sample without having to go through the previous samples if necessary. 
- Each folder contains 
    - the sample as a Ballerina notebook 
    - the sample as an MD file.
    - a separate .bal file with just the code (but this may not be a 1:1 match with the code in the notebook since the same function may be updated)
    - diagrams corresponding to the code
    

    Notes about the notebook:
    - due to some known issues in the Ballerina notebook, some snippets may not run as expected, and you may have to run the code in a separate file
    - the notebook to MD format conversion is done using [a Ballerina library](https://github.com/MaryamZi/balnb_to_md)

### Samples

| Sample | Areas Covered |
| :--: | ------------- |
|   [sample_1](sample_1)  | JSON, query expressions, JSON to record conversion, HTTP client |
|   [sample_2](sample_2)  | XML, query expressions, HTTP client |
