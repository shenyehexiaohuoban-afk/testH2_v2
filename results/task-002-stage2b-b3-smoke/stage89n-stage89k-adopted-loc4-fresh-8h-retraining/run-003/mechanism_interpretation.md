# Stage89N mechanism interpretation

Under the controlled correct-8h, loc4, penalty=1000, fresh 10-iteration setting, Stage1 production changed from `120.120000` to `109.980000 kg` (`-8.441558%`). Stage2+3 mean production changed by `-122.467678 kg`, while Stage1-3 cumulative production changed by `-132.607678 kg`. The resulting classification is `MODERATELY_REDUCED` / `LEVEL_REDUCTION`.

Stage1-3 mean ending inventory changed from `247.747481/288.280075/299.423409` to `237.607481/192.431615/179.126764 kg`. Mean ordinary shortage changed from `6.140345` to `1.541824 kg`; mean terminal gap from `6.351063` to `5.583027 kg`; mean HTT from `24.832792` to `22.511338 kg`.

This is paired controlled diagnostic evidence because the training seed and accepted Stage89H OOS path bank are exactly reused. It does not prove final convergence or that Stage89K permanently resolves early commitment.
