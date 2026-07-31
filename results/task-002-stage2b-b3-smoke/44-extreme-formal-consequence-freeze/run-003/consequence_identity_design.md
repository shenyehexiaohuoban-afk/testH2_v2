# Step-04C-A2 formal consequence identity design

The support-out identity namespace is `STEP04CA2_SUPPORT_OUT_V1`.

1. Sort the 858 exact physical paths lexicographically by the frozen 12-field key
   `(a0,loc0,lfw0,a1,loc1,lfw1,a2,loc2,lfw2,a3,loc3,lfw3)`.
2. Assign `support_out_path_rank = 1..858` and `consequence_replica_rank = 1..5`.
3. Define `joint_stream_position = 5*(path_rank-1)+replica_rank`, giving exactly
   4,290 deterministic identities. No runtime ordering or per-path seed is used.
4. Use wind seed `1704202601` and resistance seed `2704202601`. The wind stream
   supplies one independent W1-W3 quantile triplet per position. The resistance
   stream supplies one line and one road resistance vector per position. The two
   seeds are different from every nominal, validation-1, and validation-2 seed.
5. Wind follows the unchanged formal `stagewise_random_triangular` mapping.
   Line and road resistance are fixed across W1-W3, damage is persistent, and the
   formal period D/A/C construction is identical to the Step-03Y replay semantics.

The five replicas are deterministic conditional consequence realizations. They are
not empirical path probabilities and are not assigned probability mass here.
