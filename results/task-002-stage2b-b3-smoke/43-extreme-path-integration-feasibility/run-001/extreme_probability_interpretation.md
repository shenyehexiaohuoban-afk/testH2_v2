
# Probability interpretation

Every candidate has a positive legal Markov path probability. Recalculation agrees with the stored value to maximum absolute error `1.01643953670516e-20` and relative error `3.664227035405925e-15`.

Probability sums are reported separately for each initial state. Within one state, distinct complete W1-W3 paths are mutually exclusive, so the sum is the probability of exactly the selected path subset. It is not the probability of a complete, independently defined extreme event because the subset was selected after applying four proxy-tail and Pareto rules. Sums across the 35 conditional initial states are not a probability unless an initial-state distribution is supplied.

Theoretical `path_probability` must not replace the empirical `1/15000` mass of the nominal sample. For support-out paths it also does not identify the missing wind/resistance random-stream realization needed for formal D/A/C.
