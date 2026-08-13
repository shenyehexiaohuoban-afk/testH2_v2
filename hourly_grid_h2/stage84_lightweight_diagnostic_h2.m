function d = stage84_lightweight_diagnostic_h2(lib, p, seed, nPaths)
%STAGE84_LIGHTWEIGHT_DIAGNOSTIC_H2 Read-only structural policy diagnostic.

if nargin < 4, nPaths = 40; end
rng(seed, 'twister');
sitePel = zeros(1,4); sitePelN = zeros(1,4); siteLimited = zeros(1,4);
minV = inf; maxV = -inf; maxUtil = 0; maxEq = 0; maxIneq = 0;
maxInv = 0; maxHtt = 0; invalidDual = 0; solverErrors = 0;
terminalErrors = 0; gridViolations = 0; operatingSolves = 0;

for q = 1:nPaths
    prev = p.x_0; k = p.k_init; absorbed = false;
    for t = 1:p.T
        if t > 1, k = mc_sample(k, p.P_joint); end
        if absorbed, continue; end
        if p.is_dissipated(k) || p.is_absorbing(k)
            absorbed = true; continue;
        end
        if p.is_loh_demand_stage(k)
            [terminalCost, terminalInfo] = eval_terminal_loh_h2(prev,p,k);
            if ~isfinite(terminalCost) || any(terminalInfo.shortage < -1e-12)
                terminalErrors = terminalErrors + 1;
            end
            absorbed = true; continue;
        end
        if t > p.hourly_grid.n_operating_stages
            terminalErrors = terminalErrors + 1; continue;
        end
        try
            m = update_rhs_h2(lib.models{t,k},p,k,t,prev);
            s = solve_stage_model_h2(m); operatingSolves = operatingSolves + 1;
        catch
            solverErrors = solverErrors + 1; continue;
        end
        if any(~isfinite(s.lambda.inventory_eq)) || numel(s.lambda.inventory_eq) ~= 4
            invalidDual = invalidDual + 1;
        end
        eq = m.Aeq*s.xraw-m.beq; ineq = m.A*s.xraw-m.b;
        v = sqrt(max(s.v_sq,0)); trueS = hypot(s.p_branch_kw,s.q_branch_kvar)/1000;
        maxEq=max(maxEq,max(abs(eq))); maxIneq=max(maxIneq,max([0;ineq]));
        maxInv=max(maxInv,max(abs(eq(m.rowMap.inventory_eq))));
        maxHtt=max(maxHtt,max([0;ineq(m.rowMap.htt_capacity)]));
        minV=min(minV,min(v,[],'all')); maxV=max(maxV,max(v,[],'all'));
        maxUtil=max(maxUtil,max(trueS,[],'all')/p.hourly_grid.branch_smax_mva);
        if min(v,[],'all') < p.hourly_grid.vmin_pu-1e-7 || ...
                max(v,[],'all') > p.hourly_grid.vmax_pu+1e-7 || ...
                max(trueS,[],'all') > p.hourly_grid.branch_smax_mva+1e-7
            gridViolations=gridViolations+1;
        end
        sitePel=sitePel+sum(s.p_el_hourly_kw,2).';sitePelN=sitePelN+8;
        for site=1:4
            bus=p.hourly_grid.site_elec_bus(site);
            for h=1:8
                below=s.p_el_hourly_kw(site,h)<p.el_cap_kw(site)-1e-6;
                vTight=v(bus,h)<=p.hourly_grid.vmin_pu+1e-5;
                bTight=max(trueS(:,h))/p.hourly_grid.branch_smax_mva>=0.999;
                siteLimited(site)=siteLimited(site)+double(below&&(vTight||bTight));
            end
        end
        prev=s.xval;
    end
end

[cutPass,cutCount]=cut_audit(lib,p);
d=struct('n_paths',nPaths,'operating_solves',operatingSolves,'solver_errors',solverErrors, ...
    'invalid_duals',invalidDual,'terminal_semantics_errors',terminalErrors, ...
    'grid_violations',gridViolations,'max_eq_error',maxEq,'max_ineq_violation',maxIneq, ...
    'max_inventory_error',maxInv,'max_htt_violation',maxHtt,'minimum_voltage_pu',minV, ...
    'maximum_voltage_pu',maxV,'maximum_branch_utilization',maxUtil, ...
    'cut_dimension_pass',cutPass,'cut_count',cutCount,'state_dimension',p.Ni);
d.site_average_p_el_kw=sitePel./max(1,sitePelN);
d.site_grid_limited_frequency=siteLimited./max(1,sitePelN);
d.pass=solverErrors==0&&invalidDual==0&&terminalErrors==0&&gridViolations==0&& ...
    maxEq<=1e-6&&maxIneq<=1e-6&&maxInv<=1e-6&&maxHtt<=1e-6&&cutPass&&p.Ni==4&& ...
    all(cellfun(@isempty,lib.models(7:8,:)),'all');
end

function [pass,count]=cut_audit(lib,p)
pass=true;count=0;base=5+8*8*p.hourly_grid.n_branch;
for t=1:6
    for k=1:p.K
        m=lib.models{t,k};if isempty(m),continue;end
        count=count+max(0,size(m.A,1)-base);
        allowed=false(1,m.nvars);allowed(m.idx.x)=true;allowed(m.idx.theta)=true;
        for r=base+1:size(m.A,1)
            pass=pass&&numel(m.idx.x)==4&&nnz(m.A(r,~allowed))==0;
        end
    end
end
end
