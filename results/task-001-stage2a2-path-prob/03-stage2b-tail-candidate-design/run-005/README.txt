Step-02B-3 run-005: physical tail-path deduplication and labels

status=PASS; PASS=13; FAIL=0
input_records=4005
unique_physical_paths=1126
duplicate_records_removed=2879
one_two_three_levels=99/48/979
observed_unobserved_overlap=0
probability_tolerance=1e-12
q95_unique_paths=1126
q99_unique_paths=1027
q995_unique_paths=979
grid_max_unique_paths=310
grid_excess_unique_paths=779
road_max_unique_paths=310
road_excess_unique_paths=811

One physical path is defined only by the complete initial/W1/W2/W3 state sequence.
All quantile, proxy, and observed/unobserved labels are retained; no representative path is selected.
No resampling, wind calculation, legal-path search, B3, D/A/C, WDRO, Gurobi, or MSP.
