# Stage90B Base-Pmax fresh zero-cut 10-iteration smoke

- Candidate: Pmax=[300,200,120,150] kW, penalty 1000 yuan/kg, terminal redistribution ON, K_terminal=160 kg.
- Freshness: separate CONFIG/TRAIN/RELOAD MATLAB processes; initial cut count 0; exactly 10 iterations.
- Terminal LP was exercised by forward records, backward state evaluations, and one-path OOS through the shared evaluator.
- TERMINAL_RECOURSE_USED = YES; K160_BINDING_SIGNAL = NONE.
- Early mechanism signals only: binding count 0; no performance, wait-and-see, or reliability claim is made.
- Stage1 QA: min voltage 0.912081659, max line utilization 0.682695583, max substation utilization 0.753348711, max HTT utilization 0.
- NEW_BLOCKING_ISSUE = NO if CONFIG/TRAIN/RELOAD markers and all finite QA files pass.
- Source commit: 25f4745c265a256bb1d886a2e4be10137be578fe; terminal lookup SHA-256: 2fa1958944110701239a109ebf46d959324a351f2f27c1c3fbd62f333066eaa8.
