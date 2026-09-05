function [flag, elapsed, relative_gap] = termination_check(iter, LB, start_time, cutviol_iter, params)
%TERMINATION_CHECK  Check stopping criteria for MSP/FA training.
%
% flag:
%   0 = continue training
%   1 = max iteration reached
%   2 = time limit reached
%   3 = too many consecutive iterations without cut violation
%   4 = lower bound has stalled

flag = 0;
elapsed = toc(start_time);
relative_gap = inf;

if iter >= params.max_iter
    flag = 1;
    return;
end

if elapsed > params.time_limit
    flag = 2;
    return;
end

if cutviol_iter > params.cutviol_maxiter
    flag = 3;
    return;
end

if iter > params.stall
    oldLB = LB(iter - params.stall);
    newLB = LB(iter);

    denom = max(1e-10, abs(oldLB));
    relative_gap = (newLB - oldLB) / denom;

    if relative_gap < params.eps_tol
        flag = 4;
        return;
    end
end

end
