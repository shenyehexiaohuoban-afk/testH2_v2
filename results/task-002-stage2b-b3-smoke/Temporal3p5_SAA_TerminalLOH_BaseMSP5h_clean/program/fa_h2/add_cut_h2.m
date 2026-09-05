function model = add_cut_h2(model, g, alpha)
%ADD_CUT_H2 Add one future-value cut theta >= alpha + g' * x.

row = zeros(1, model.nvars);
row(model.idx.x) = g(:).';
row(model.idx.theta) = -1;
model.A(end + 1, :) = row;
model.b(end + 1, 1) = -alpha;
end
