
# Solver compatibility

An extreme-max term could be added to the Step-04B certified decomposition by evaluating all defined extreme recourse functions at each trial `T`, taking the maximum, and adding a valid Danskin subgradient cut. Lower and upper bounds remain meaningful if the master contains the extreme-risk epigraph and every upper-bound evaluation is exact.

No solver integration was attempted because support-out formal D/A/C is missing. The production Step-04B solver core was not modified.
