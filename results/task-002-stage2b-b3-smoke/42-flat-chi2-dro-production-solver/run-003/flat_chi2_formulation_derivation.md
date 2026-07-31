# Flat chi-square formulation derivation

For f(t)=(t-1)^2 on t>=0, f*(s)=-1+(max(s+2,0))^2/4.

The exact risk epigraph is nu+lambda*(eta-1)+sum(q_r h_r), with t_r>=z_r-nu+2 lambda, t_r>=0, h_r>=0, and t_r^2<=4 lambda h_r.

Eta zero calls SAA directly. At lambda zero the cone forces t=0 and nu>=max(z), so the closed perspective is represented without division. For eta>0, p=q is a Slater point and strong duality holds. The frozen recourse LP is feasible through shortage variables and bounded by finite demand and capacity.

Exact duplicate aggregation uses all raw three-period D/A/C bytes and q_g=m_g/R. Identical recourse functions make grouped and original SAA/DRO problems exactly equivalent; probability recovered for each original record is group mass divided by multiplicity.
