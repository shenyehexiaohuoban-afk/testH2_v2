
# Extreme selection rule audit

Selection is a directed proxy search, not sampling from a new probability law. A path is first required to have a positive proxy value at or above its state-specific q95, q99, or q99.5 threshold. Pareto filtering is performed separately for each state/proxy/level with objectives `path_probability` lower and proxy risk higher. The four proxy Pareto labels and three levels are then unioned and retained through exact physical-path deduplication.

Consequences:

- the 4005 source rows are labels, not 4005 independent paths;
- the final 1126 paths are selection-biased toward proxy tails;
- the theoretical path probabilities remain audit fields and were never empirical candidate weights;
- proxy selection does not establish actual recourse harm.
