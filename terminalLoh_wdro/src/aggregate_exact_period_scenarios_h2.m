function out = aggregate_exact_period_scenarios_h2(Dperiod, Aperiod, Cperiod)
%AGGREGATE_EXACT_PERIOD_SCENARIOS_H2 Exact byte-level D/A/C aggregation.
%
% Hashes are used only to create candidate buckets. Every member of a
% bucket is then compared against its representative using the exact raw
% bytes of all formal three-period D/A/C inputs. No rounding, tolerance,
% path identity, or fixed-T loss is used.

[R, K, N] = size(Dperiod);
I = size(Aperiod, 3);
if R < 1 || ~isequal(size(Aperiod), [R, K, I, N]) || ...
        ~isequal(size(Cperiod), [R, K, I, N])
    error('aggregate_exact_period_scenarios_h2:BadArraySize', ...
        'Expected D=R x K x N and A/C=R x K x I x N.');
end
if any(~isfinite(Dperiod), 'all') || any(Dperiod < 0, 'all') || ...
        any(Aperiod > 0.5 & ~isfinite(Cperiod), 'all')
    error('aggregate_exact_period_scenarios_h2:BadInput', ...
        'Formal D/A/C inputs are invalid.');
end

started = tic;
hashes = strings(R, 1);
for rr = 1:R
    hashes(rr) = scenario_hash(Dperiod(rr, :, :), ...
        Aperiod(rr, :, :, :), Cperiod(rr, :, :, :));
end

[uniqueHashes, ~, hashBucket] = unique(hashes, 'stable');
groupId = zeros(R, 1);
representative = zeros(R, 1);
multiplicity = zeros(R, 1);
groupHash = strings(R, 1);
groupCount = 0;
collisionSplitCount = 0;

for hh = 1:numel(uniqueHashes)
    members = find(hashBucket == hh);
    localRepresentatives = zeros(numel(members), 1);
    localGroupIds = zeros(numel(members), 1);
    localCount = 0;
    for jj = 1:numel(members)
        rr = members(jj);
        matched = false;
        for gg = 1:localCount
            rep = localRepresentatives(gg);
            if scenario_bytes_equal(Dperiod, Aperiod, Cperiod, rr, rep)
                groupId(rr) = localGroupIds(gg);
                matched = true;
                break;
            end
        end
        if ~matched
            localCount = localCount + 1;
            groupCount = groupCount + 1;
            localRepresentatives(localCount) = rr;
            localGroupIds(localCount) = groupCount;
            groupId(rr) = groupCount;
            representative(groupCount) = rr;
            groupHash(groupCount) = uniqueHashes(hh);
        end
    end
    collisionSplitCount = collisionSplitCount + max(0, localCount - 1);
end

representative = representative(1:groupCount);
groupHash = groupHash(1:groupCount);
multiplicity = accumarray(groupId, 1, [groupCount, 1]);
qGroup = multiplicity ./ R;

for rr = 1:R
    if ~scenario_bytes_equal(Dperiod, Aperiod, Cperiod, rr, ...
            representative(groupId(rr)))
        error('aggregate_exact_period_scenarios_h2:VerificationFailure', ...
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
out.group_hash_sha256 = groupHash;
out.Dperiod = Dperiod(representative, :, :);
out.Aperiod = Aperiod(representative, :, :, :);
out.Cperiod = Cperiod(representative, :, :, :);
out.maximum_multiplicity = max(multiplicity);
out.duplicate_record_count = R - groupCount;
out.aggregation_ratio = groupCount / R;
out.hash_collision_split_count = collisionSplitCount;
out.exact_verification_pass = true;
out.runtime_sec = toc(started);
end

function tf = scenario_bytes_equal(D, A, C, left, right)
tf = isequal(typecast(double(reshape(D(left, :, :), [], 1)), 'uint64'), ...
    typecast(double(reshape(D(right, :, :), [], 1)), 'uint64')) && ...
    isequal(uint8(reshape(A(left, :, :, :), [], 1)), ...
    uint8(reshape(A(right, :, :, :), [], 1))) && ...
    isequal(typecast(double(reshape(C(left, :, :, :), [], 1)), 'uint64'), ...
    typecast(double(reshape(C(right, :, :, :), [], 1)), 'uint64'));
end

function hash = scenario_hash(D, A, C)
md = java.security.MessageDigest.getInstance('SHA-256');
update_digest(md, typecast(double(D(:)), 'uint8'));
update_digest(md, uint8(A(:)));
update_digest(md, typecast(double(C(:)), 'uint8'));
digest = typecast(md.digest(), 'uint8');
hash = lower(string(reshape(dec2hex(digest, 2).', 1, [])));
end

function update_digest(md, bytes)
md.update(typecast(uint8(bytes(:)), 'int8'));
end
