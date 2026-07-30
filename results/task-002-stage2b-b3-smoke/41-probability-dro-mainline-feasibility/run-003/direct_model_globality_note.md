
# Direct microtree globality note

Every microtree conditional distribution is binary. Its Pearson chi-square ball is an exact closed interval for the left-child probability. The complete leaf expectation is multilinear in these interval variables, so a global maximum occurs at an interval endpoint for every internal node. The validation enumerates all `2^m` endpoint combinations (`m` internal nodes); this is a finite global proof for the tested trees, not a local nonlinear solve. Both test trees meet the `1e-8` objective-difference threshold.
