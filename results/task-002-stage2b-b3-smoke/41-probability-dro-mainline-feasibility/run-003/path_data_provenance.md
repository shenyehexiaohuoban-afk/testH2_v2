
# Path data and probability provenance

## Recovered mechanism

The 35 initial states are the Cartesian product `a0=2..6`, `loc0=1..7`, and fixed `lfw0=0`. For each initial state, the accepted generator uses the fixed main seed `20260706`, derives a state-specific MT19937 seed, and draws 15,000 independent records. Intensity, location, and lfw are sampled as three separate discrete Markov chains for W1-W3; the joint native state is their exact tuple `(a,loc,lfw)`.

This is ordinary conditional Monte Carlo. It is not enumeration, importance sampling, resampling, or filtering. The accepted file contains 525,000 records and exactly 15,000 records for each of 35 states.

## Probability distinction

The generator stores `path_probability` as the product of the three component transition probabilities along the exact W1-W3 chain. The maximum reconstruction error found in this audit is `9.9638179651417857e-17`.

The frozen Step-03J nominal SAA/WDRO data instead assigns every record the empirical weight `1/15000`. Therefore the observed-support nominal leaf probability used in Step-04A is `frequency/15000` after exact duplicate aggregation. Applying `path_probability` again would double-count the Markov law. The observed unique theoretical probabilities do not sum to one because the 15,000-record Monte Carlo sample does not cover the full theoretical path support.

No importance-sampling weight, likelihood ratio, or other probability correction field exists.
