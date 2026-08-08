function out = aggregate_exact_period_scenarios_c6_nojvm_h2(Dperiod, Aperiod, Cperiod)
%AGGREGATE_EXACT_PERIOD_SCENARIOS_C6_NOJVM_H2 Exact raw-byte aggregation.
%
% This C6-only implementation avoids Java/.NET per-scenario hashes. It
% constructs the complete raw byte row for every formal three-period D/A/C
% scenario and applies exact row equality. No rounding, tolerance, path
% identity, probability, decision, or loss information is used.

[R, K, N] = size(Dperiod);
I = size(Aperiod, 3);
if R < 1 || ~isequal(size(Aperiod), [R, K, I, N]) || ...
        ~isequal(size(Cperiod), [R, K, I, N])
    error('aggregate_exact_period_scenarios_c6_nojvm_h2:BadArraySize', ...
        'Expected D=R x K x N and A/C=R x K x I x N.');
end
if any(~isfinite(Dperiod), 'all') || any(Dperiod < 0, 'all') || ...
        any(Aperiod > 0.5 & ~isfinite(Cperiod), 'all')
    error('aggregate_exact_period_scenarios_c6_nojvm_h2:BadInput', ...
        'Formal D/A/C inputs are invalid.');
end

started = tic;
dExample = typecast(double(reshape(Dperiod(1, :, :), [], 1)), 'uint8');
aExample = uint8(reshape(Aperiod(1, :, :, :), [], 1));
cExample = typecast(double(reshape(Cperiod(1, :, :, :), [], 1)), 'uint8');
byteCount = numel(dExample) + numel(aExample) + numel(cExample);
raw = zeros(R, byteCount, 'uint8');
for rr = 1:R
    dBytes = typecast(double(reshape(Dperiod(rr, :, :), [], 1)), 'uint8');
    aBytes = uint8(reshape(Aperiod(rr, :, :, :), [], 1));
    cBytes = typecast(double(reshape(Cperiod(rr, :, :, :), [], 1)), 'uint8');
    raw(rr, :) = [dBytes(:); aBytes(:); cBytes(:)].';
end

[~, representativeSorted, groupSorted] = unique(raw, 'rows');
[representative, stableOrder] = sort(representativeSorted);
oldToStable = zeros(numel(stableOrder), 1);
oldToStable(stableOrder) = (1:numel(stableOrder)).';
groupId = oldToStable(groupSorted);
groupCount = numel(representative);
multiplicity = accumarray(groupId, 1, [groupCount, 1]);
qGroup = multiplicity ./ R;

for rr = 1:R
    if ~isequal(raw(rr, :), raw(representative(groupId(rr)), :))
        error('aggregate_exact_period_scenarios_c6_nojvm_h2:VerificationFailure', ...
            'Scenario %d differs from its exact representative.', rr);
    end
end

out = struct();
out.original_R = R;
out.group_count = groupCount;
out.group_id = groupId;
out.representative_index = representative;
out.multiplicity = multiplicity;
out.nominal_probability = qGroup;
out.group_hash_sha256 = strings(groupCount, 1);
out.group_key_method = "exact_raw_byte_rows";
out.Dperiod = Dperiod(representative, :, :);
out.Aperiod = Aperiod(representative, :, :, :);
out.Cperiod = Cperiod(representative, :, :, :);
out.maximum_multiplicity = max(multiplicity);
out.duplicate_record_count = R - groupCount;
out.aggregation_ratio = groupCount / R;
out.hash_collision_split_count = 0;
out.exact_verification_pass = true;
out.runtime_sec = toc(started);
end
