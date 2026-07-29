# Recovered D + Ctilde Ground Cost Definition

Authoritative implementation: `terminalLoh_wdro/src/step03S_distance_block_h2.m`.

## Frozen aggregate definition

For scenarios r and s, `rawD=sum_n abs(D_r(n)-D_s(n))`. If the state D scale is at most 1e-12, `d_D=0`; otherwise `d_D=rawD/(Dscale+1e-9)`.

For every one of the 4 x 33 site-node relations, Ctilde uses:
- both unreachable: local distance 0; invalid C payloads are ignored
- exactly one reachable: local distance kappa=1
- both reachable: local distance abs(C_r-C_s)/C_bound

The 132 local values are averaged. `C_bound=357.1526447416079 km`, `d_new=0.6*d_D+0.4*d_Ctilde`. There is no standalone A component and no truncation.

## Three-period extension audited here

W1 is compared only with W1, W2 only with W2, and W3 only with W3. Each period uses the frozen aggregate formula and the same state Dscale. The official audit convention is the arithmetic mean of the three period components:

`d_D_period=(d_D_W1+d_D_W2+d_D_W3)/3`

`d_Ctilde_period=(d_Ctilde_W1+d_Ctilde_W2+d_Ctilde_W3)/3`

`d_period=0.6*d_D_period+0.4*d_Ctilde_period`.

Using the sum instead of the mean produces exactly `3*d_period`, so rankings are identical. The mean is used to avoid an unintended threefold scale expansion.
