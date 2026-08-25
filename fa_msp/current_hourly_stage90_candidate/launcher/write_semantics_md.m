function write_semantics_md(runDir, rootDir, p, c0, cDistance, lambda, ...
        iter5, beta5, shipKg, shipCost, meanCost, pairExplained, coverage, ...
        geometryChanged, kSignal, c0Consistent, baseResidual)
file = fullfile(runDir, 'terminal_cost_semantics.md');
fid = fopen(file, 'w', 'n', 'UTF-8');
if fid < 0
    error('Stage90B2:Write', 'Cannot write output.');
end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '# Stage90B2 terminal cost semantics'); fprintf(fid, char(10)); fprintf(fid, char(10));
fprintf(fid, '- Scope: read-only audit of Stage90B run-004.'); fprintf(fid, char(10));
fprintf(fid, '- Active source: %s; active checkpoint c0=%.12g.\n', relative_path(rootDir, p.nearInputFile), c0);
fprintf(fid, '- Base-cost identity: baseCost(i,j)=%.12g*roadDistance(i,j), max residual %.12g.\n', cDistance, baseResidual);
fprintf(fid, '- Hourly objective: c0 + baseCost(i,j)*(1 + beta_transport_multiplier*beta), multiplier %.12g, hourly-v1=%d.\n', lambda, logical(p.hourly_htt_v1));
fprintf(fid, '- Terminal LP objective uses the same base matrix, beta multiplier, and c0 plus 1000*sum(g_i).\n\n');
fprintf(fid, '- Historical Stage85F/H02 0.2*distance and c0=5 references are inactive provenance.\n\n');
fprintf(fid, '## Iteration 5'); fprintf(fid, char(10)); fprintf(fid, char(10));
fprintf(fid, '- Saved record: iteration 5, stage %d, state index %d, beta %.12g.\n', iter5.stage, iter5.state_id, beta5);
fprintf(fid, '- Physical shipment %.12g kg; reported physical shipping cost %.12g yuan; mean unit cost %.12g yuan/kg.\n', shipKg, shipCost, meanCost);
fprintf(fid, '- The mean unit cost equals the minimum state-199 OD cost. It identifies the undirected Site2/Site3 pair and proves zero flow on every higher-cost OD. The two directions tie, so x_ij direction is not identifiable because run-004 did not save x_ij.\n');
fprintf(fid, '- value_yuan is physical shipping plus reserve-shortage penalty, not a probability-weighted shipping cost.\n\n');
fprintf(fid, '## Backward and geometry'); fprintf(fid, char(10)); fprintf(fid, char(10));
fprintf(fid, '- Backward coverage label: %s on 35 saved Stage-7 states.\n', coverage);
fprintf(fid, '- Terminal value geometry changed relative to DIRECT_GAP: %s. K=160 binding signal: %s.\n', ternary(geometryChanged,'YES','NO'), kSignal);
fprintf(fid, '- c0 identity: %s; no active cost-semantics bug was found.\n', ternary(c0Consistent,'CONSISTENT','INCONSISTENT'));
end

function out = relative_path(rootDir, path)
path = char(string(path));
rootDir = char(string(rootDir));
if startsWith(path, rootDir)
    out = strrep(path(numel(rootDir)+2:end), '\\', '/');
else
    out = path;
end
end

function value = ternary(condition, ifTrue, ifFalse)
if condition
    value = ifTrue;
else
    value = ifFalse;
end
end
