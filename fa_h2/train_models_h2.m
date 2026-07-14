function [modelLib, trainInfo] = train_models_h2(modelLib, params)
%TRAIN_MODELS_H2 Train the hydrogen FA-MSP policy.
%
% This keeps the original offline FA/SDDP-style loop: forward sample path,
% lower-bound record, termination check, then backward cut sharing.

lb = 0;
LB = zeros(0, 1);
xval = zeros(params.Ni, params.T);
thetaval = zeros(params.T, 1);
iter = 0;
cutviol_iter = 0;
relative_gap = inf;
start_time = tic;
terminate_flag = 0;

while true
    iter = iter + 1;

    [modelLib, xval, thetaval, lb, in_sample, forwardInfo] = forward_pass_h2( ...
        modelLib, params, lb, xval, thetaval);
    LB(end + 1, 1) = lb; %#ok<AGROW>

    if numel(LB) >= 2 && LB(end) < LB(end - 1) - 1e-6
        warning('train_models_h2:LBDecrease', ...
            'LB decreased at iter %d: previous %.12g, current %.12g.', ...
            iter, LB(end - 1), LB(end));
    end

    fprintf('H2 Iter %d: LB = %.6f\n', iter, lb);

    [terminate_flag, elapsed, relative_gap] = termination_check( ...
        iter, LB, start_time, cutviol_iter, params);
    if terminate_flag ~= 0
        break;
    end

    [modelLib, cutviolFlag] = backward_pass_h2(modelLib, params, xval, thetaval, in_sample);
    if cutviolFlag == 1
        cutviol_iter = 0;
    else
        cutviol_iter = cutviol_iter + 1;
    end
end

trainInfo = struct();
trainInfo.LB = LB;
trainInfo.train_time = elapsed;
trainInfo.iter = iter;
trainInfo.terminate_flag = terminate_flag;
trainInfo.stop_flag = terminate_flag;
trainInfo.relative_gap = relative_gap;
trainInfo.last_xval = xval;
trainInfo.last_thetaval = thetaval;
trainInfo.last_forward = forwardInfo;
trainInfo.cutviol_iter = cutviol_iter;
end
