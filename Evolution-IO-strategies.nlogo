extensions[
  table
] ;a table in Netlogo is a dictionary data structure

globals [
  ;rng-seed-value - for reproducibility
  ;simulation length - controlled by slider
  ;initial-membership-count
  ;history
  ;mutation-rate
  possible-priorities ; All the issues that states care and can potentially cooperate on in the simulation
  scope ; number of issues the organization considers at one time
  IO-revenue ; balance of IO income and expenses in a given round
  IO-previous-revenue;
  IO-previous-members;
  IO-wealth ; running sum of revenue and expenses
  IO-operating-cost ; sum of fixed and variable costs
  IO-investments ;
  IO-priorities ; the issues that the organization is actively considering at a given point in time
  issue-index; a table that matches issue names with the array values that turtles use to store them
  voting-body ;All the members eligible to participate in a given vote
  priority-votes; a table containing the current votes for each issue
  membership-votes; a table containing the current votes for each issue
  possible-membership-rules; for now, a list of membership rules for states to choose from
  active-membership-rules; the membership rules that are currently being used
  defection-limit
]

turtles-own [
  my-priorities ; the numeric importance of each issue area to the state
  my-priorities-order ; the name of each area from most to least important
  my-income ;how much the state has avaible to invest in a given turn
  my-utility ;how much subjective value the state gets from spending (or saving) income
  my-shadow-future ;utility scaling factor for defection that represents
  my-beliefs-contribution ; how much the state believes that others will pay what is asked
]

breed [ members member ]
breed [ non-members non-member ]

members-own [
  my-join-turn
  my-IO-contribution
  my-IO-payoffs ;how much the IO pays off for each issue area
  my-priority-vote ; the issue the state tells the IO to focus on
  my-membership-vote ; what rules does this state want for new members
  my-defection-monitoring-vote; how much of the IO's budget this state wants to go toward catching defection (and not the actual problem)
  my-permitted-defections-vote; how many chances this state wants the IO to give defectors
  eligible-for-payout ; a boolean for whether or not the state was caught contributing less than the minimum
  my-times-caught ; how many times the state has been caught defecting
]

;Clear board, generate states according to distributions andform IO based on initial parameters
to setup
  ca
  reset-ticks
  set-default-shape turtles "square"
  random-seed rng-seed
  set possible-priorities (list "security" "trade" "human-rights" "environment" "culture")
  initialize-issue-index
  initialize-states
  initialize-IO
end

;Member states participate in a club goods game while nonmembers only have the option to join or not join
to go
  if (IO-wealth <= 0 or (ticks >= simulation-length) or count members <= 1) [stop] ;stop if the IO goes bankrupt or time runs out
  ;if endogenous flexibility behavior is ever implemented this section will neeed to be expanded upon
  set defection-limit default-permitted-defections
  vote-rules-and-agenda ; can turn off voting by commenting this line out
  ask members [
    clear-payoffs
    set eligible-for-payout true
    decide-contribution
  ]
  set IO-revenue 0
  play-one-round
  update-IO-records
  update-membership
  mutations
  tick
end

;observer context -make one state per patch on grid
to initialize-states
  ask patches [sprout 1 [initialize-state]]
end

;turtle context - each state has an initial set of preferences and beliefs about other states
to initialize-state
  set my-income state-income
  set my-beliefs-contribution 1; states begin with full faith in IO
  initialize-state-priorities
  leave-institution
end

;turtle context
;create a preference distribution for each state either by ordering issues or distributing points
to initialize-state-priorities
    set my-priorities [ 0 0 0 0 0 ]
    let points 100
    while [ points > 0 ] ; increase random category values one by one until points run out
    [
      let increased-priority random length my-priorities ;pick one issue
      ;item command uses index and then list to retrieve value
      set my-priorities replace-item increased-priority my-priorities (item increased-priority my-priorities + 1)
      set points points - 1
    ]
  set my-priorities-order my-ordered-priorities
end

;Record the initial parameters (which can be changed using the interface sliders)
to initialize-IO
  set scope next-scope
  set IO-wealth initial-IO-wealth
  set IO-operating-cost IO-fixed-cost
  set IO-priorities sublist possible-priorities 0 scope
  set IO-investments zero-all-issues
  ask n-of initial-membership-count turtles [join-institution]
  set priority-votes table:make
  foreach possible-priorities [issue -> table:put priority-votes issue 0]
  set-new-IO-priorities
  set IO-previous-revenue 1
  set IO-previous-members 1
end

;Ultimately, states should be able to choose cotributions from a continuous space. However, the biggest challenge comes from
;the analytic knowledge that defection is the dominant strategy in public goods games and the observed pattern of state cooperation
;in the real world.
to decide-contribution
  ;ultimately we want to find arg max of EV(contribution) within restricted domain but to do that we accurately we should find a library for calculus
  ;The following is a naive finite approximation of that process that runs rather slowly with large numbers of members and small increments
  let current-contribution min-contribution
  let best-contribution min-contribution
  let issue first IO-priorities
  let best-EV my-expected-utility-single state-income best-contribution
  while [current-contribution <= my-income + .001 ] ;floating-point manissa
  [
    let EV-current my-expected-utility-single state-income current-contribution ; recording function val to avoid recalculating
    if (EV-current >= best-EV)
    [ set best-contribution current-contribution
      set best-EV EV-current
    ]
    set current-contribution current-contribution + optimization-resolution
  ]
  set my-IO-contribution best-contribution
  ;assuming the IO has the power to kick out any state that tries to cheat and not paying is still more advantage
  if (min-contribution >= 0.0 and best-EV < my-expected-utility-single state-income 0) [set my-IO-contribution 0 ]
end

;This is really a multivariable function that takes the requested contribution, a proposed contribution, a state's beliefs about other states' cooperation,
;the expected costs and multipliers for the IO's number one priority. Depending on how much we are subdividing the contributions it might make more sense to
;precalculate the max for all possible configurations and then just have the states look that up.
to-report my-expected-utility-single [requested proposed]
  let funds expected-IO-investible + proposed
  let expected-payout-single-issue 0
  let x first IO-priorities
  if (funds >= issue-cost x)
  [set expected-payout-single-issue (item (index x) my-priorities / 20 * (issue-benefit x * funds / count members))]

  let dp defection-percent proposed
  let w 1 - (dp * my-shadow-future) ;an estimate of future harm that might come from short-term gain
  let EV-investment (expected-payout-single-issue - proposed) * w
  let remaining my-income - proposed ;assume that any leftover funds have a utility of 1:1
  report  EV-investment + remaining
end

;turtle or observer context
to-report expected-IO-investible
  report expected-IO-income-others - expected-IO-costs + IO-wealth
end

;this is the same as actual costs for now
to-report expected-IO-costs
  report IO-fixed-cost + IO-variable-cost
end

to-report expected-IO-income-others
  report (my-beliefs-contribution * state-income * (count members - 1))
end

;Gather all the states contributions, subtract operating costs and minimum thresholds, apply multipliers and then distribute dividends
to play-one-round
  ;IO first collects all contributions
  ask members
  [
    set IO-revenue IO-revenue + my-IO-contribution
  ]
  ;Whether the organization pays its costs before or after the investment step is actually important and should be revisited late
  allocate-IO-funds
  pay-member-states
end

;It's not strictly necessary to use a dictionary to represent the issue indices
;but having indices as list values will get confusing when the order of IO priorities changes
to initialize-issue-index
  set issue-index table:make
  table:put issue-index "security" 0
  table:put issue-index "trade" 1
  table:put issue-index "human-rights" 2
  table:put issue-index "environment" 3
  table:put issue-index "culture" 4
end

;turtle context
to-report my-ordered-priorities
  report sort-by [ [p1 p2] ->  item table:get issue-index p1 my-priorities  >  item table:get issue-index p2 my-priorities] possible-priorities
end

;observer context
;A way to relate the IO's cost of operation with the size of the organization.
;For now, the default scaling is linear, but other options can be implemented by adding a chooser in the interface and if statements here, if desired
to-report IO-variable-cost
  let n count members
  ;linear
  report n * structure-cost-multiplier
end

to allocate-IO-funds
  set IO-operating-cost (IO-fixed-cost + IO-variable-cost)
  set IO-wealth IO-wealth + IO-revenue - IO-operating-cost
  let investible IO-wealth - 1
  set IO-investments zero-all-issues
  if (investible >= 1)
  [
  set IO-wealth IO-wealth - investible
  initialize-investments
  if (allocation-strategy = "first priority") [invest-in-first-priority investible]
  ]
end

;turtle (member) context
;A reporter that can be used to decide if a state wants to push for (costly) reforms or leave the IO
;The specifics of the criteria might be a variable themselves but its important to have a way to change the structure of the IO and this is one of the easiest
to-report satisfied-with-IO
  report my-utility >= my-IO-contribution
end

;turtle context
;this should reflect a state's internal motivation to join the IO; for now just use chance
to-report want-to-join
  report random-float 1.0 < apply-rate
end

;turtle context
;first check that there are members and then analyze various attributes of the candidates
to-report meet-criteria
  let required-priority-level 0;
  let low low-minimum-membership-priority
  let high low + priority-threshold-difference
  ifelse (
    (membership-priority-meta = "always high") or
    (membership-priority-meta = "higher beyond threshold" and count members >= membership-change-threshold) or
    (membership-priority-meta = "lower beyond threshold" and count members < membership-change-threshold))
    [set required-priority-level high]
  [set required-priority-level low]
  report item index first IO-priorities my-priorities >= required-priority-level
end

;observer context
to pay-member-states
  ; defection needs to be caught before dispersal
  punish-defectors
  foreach IO-priorities [
    priority -> let funds investment-in priority
    let cost issue-cost priority
    let payout 0
    if (any? members with [ eligible-for-payout] and funds >= cost )
    [set payout (funds * issue-benefit priority) / count members]
    ask members with [eligible-for-payout] [ set my-IO-payoffs replace-item (index priority) my-IO-payoffs payout ]
  ]
end

to punish-defectors
    ; defection needs to be caught before dispersal
  ask members [
    if (random-float 1.0 < catch-defection-rate) ;if states get caught contributing less than the minimum they get punished
    [
      ifelse (my-IO-contribution < min-contribution)
      [
      set eligible-for-payout false
      set my-times-caught my-times-caught + 1]
      ;else
      [
        set my-times-caught my-times-caught + defection-percent my-IO-contribution
      ]
    if (my-times-caught > defection-limit) [leave-institution] ;
    ]
  ]
end

to mutations
ask turtles [if mutation-condition [mutate-preference]]
end

;turtle context
;Once a state is chosen to mutate, either rearrange the list or take points from one issue and give the to another in the ordered version
to mutate-preference
  ;choose an area to decrease
  let decreased-priority random 5
  ;Do not let values go negative
  while [ item decreased-priority my-priorities <= 0 ] [set decreased-priority random 5 ]
  ;item command uses index and then list to retrieve value
  set my-priorities replace-item decreased-priority my-priorities (item decreased-priority my-priorities - 1)

  let increased-priority random 5
  while [ increased-priority = decreased-priority ] [set increased-priority random 5 ]
  ;item command uses index and then list to retrieve value
  set my-priorities replace-item increased-priority my-priorities (item increased-priority my-priorities + 1)
  set my-priorities-order my-ordered-priorities
end

to vote-rules-and-agenda
  if (ticks mod priority-vote-rate = 0) [set-new-IO-priorities]
end

;observer context
to set-new-IO-priorities
  set scope next-scope
  set voting-body determine-voters
  foreach possible-priorities [issue -> table:put priority-votes issue 0]
  ;make a new list with the issues in order by
  if vote-type = "plurality" [plurality-vote]
  if vote-type = "instant runoff" [instant-runoff-vote]
  set IO-priorities (list first issues-sorted-by-votes)
end

;Asks states to vote for their favorite non-eliminated issue.
to plurality-vote
  ask voting-body
  [
    set my-priority-vote ""
    vote-highest-avaliable-priority [] ; all options are available
  ]
end

to update-IO-records
  set IO-previous-members count members
  set IO-previous-revenue IO-revenue
end

;Like the plurality vote, each state votes for its favorite option. However, if no majority is reached,
;there are a series of elimination rounds where the states who voted for the least favorite option are asked
;to change their votes to a secondary priority. The specific implementation is based off materials found here: https://www.fairvote.org/rcv#how_rcv_works
to instant-runoff-vote
  plurality-vote
  let ranked issues-sorted-by-votes
  let most-votes table:get priority-votes first ranked ; the issue with most votes is ranked number 1
  let deleted []
  let num-vote-areas length possible-priorities
  while [most-votes < count voting-body / 2 ]; stop when one issue has more than half the votes
  [
    let eliminated last ranked
    set deleted lput eliminated deleted
    ;ask states whose vote was eliminated to vote for next best option
    ask voting-body with [my-priority-vote = eliminated] [vote-highest-avaliable-priority deleted ]
    set num-vote-areas num-vote-areas - 1
    set ranked sublist issues-sorted-by-votes 0 num-vote-areas
    set most-votes table:get priority-votes first ranked ; re-rank the priorities based on the new vote
  ]
end

; Modify the ordered prefence list by getting rid of options that are no longer on the table and then vote
; for the most preferred option remaining. If the state previously voted for another option, for undo that vote.
to vote-highest-avaliable-priority [deleted]
  let ordered-available-priorities my-priorities-order
  foreach deleted [del -> set ordered-available-priorities remove del ordered-available-priorities]
  if length deleted >= 1 [ vote-for-issue my-priority-vote -1 ];undo previous vote by negative voting
  set my-priority-vote first ordered-available-priorities
  vote-for-issue my-priority-vote 1
end

;Incremented the number of votes in the voting record by the number of votes allocated to the state.
;For now, each state has one vote that can either be positive or negative (negative votes undo previous vote)
;but this is intentionally abstract to allow for weighted votes in the future.
to vote-for-issue [issue votes]
  let current-votes table:get priority-votes issue ;looks up the current number of votes
  table:put priority-votes issue current-votes + votes ;update table with new vote
end

;Gets the current votes for each issue from the voting record and then sorts them.
to-report issues-sorted-by-votes
  report sort-by [[issue1 issue2] -> table:get priority-votes issue1 > table:get priority-votes issue2 ]  possible-priorities
end

;Put all available funds toward whichever issue got the most votes
to invest-in-first-priority [ funds ]
  set IO-investments replace-item (index first IO-priorities) IO-investments funds
end

;Members that want to leave leave and non-members that want to join join
to update-membership
  ask members
  [
    set my-utility calculated-utility
    set my-beliefs-contribution (IO-previous-revenue / IO-previous-members) / state-income
    if not satisfied-with-IO [leave-institution] ;need to update satisfied to consider more than one turn
  ]
  ask non-members [if want-to-join and meet-criteria [join-institution]]
end

;turtle context
to join-institution
  set color green
  set breed members
  set my-join-turn ticks
  set my-IO-contribution 0
  let uninhibited-sf inhibited-shadow-future + uninhibited-offset
  ifelse (random-float 1.0 < state-type-fraction)
  [set my-shadow-future inhibited-shadow-future]
  [set my-shadow-future uninhibited-sf]
  clear-payoffs
end

to initialize-investments
  set IO-investments zero-all-issues
end
to clear-payoffs
  set my-IO-payoffs zero-all-issues
end

;turtle context
;this will also get rid of members-only variables
to leave-institution
  set color red
  set breed non-members
end

to-report investment-in [issue]
  let i index issue
  report item i IO-investments
end
;turtle context
to-report preference-for [issue]
    let i index issue
    report item i my-priorities
end

to-report index [issue]
  report table:get issue-index issue
end

;observer context
to-report determine-voters
  let members-by-contribution reverse sort-on [my-IO-contribution] members
  let IDs sublist members-by-contribution  0 (ceiling (fraction-voting * count members))
  report members with [member? self IDs]
end

to-report calculated-utility
  let ut 0
  ;weight each payoff by how much the priority deviates from a "neutral" value
  (foreach my-priorities my-IO-payoffs [[ weight payoff ] -> set ut ut + (weight * payoff / 20)])
  let dp defection-percent my-IO-contribution
  let w 1 - (dp * my-shadow-future) ;an estimate of future harm that might come from short-term gain
  report ut * w + my-income - my-IO-contribution
end

to-report defection-percent [my-contribution]
  report (state-income - my-contribution) / state-income
end

;In more specialized simulations, we will be able to experiment with having variable issue costs, but for now to simplify things all the issues have the same cost.
to-report issue-cost [issue]
  report count members * issue-cost-multiplier
end

;In more specialized simulations, we will be able to experiment with having variable issue benefits, but for now to simplify things all the issues have the same cost
to-report issue-benefit[issue]
  report benefit-multiplier
end

to-report zero-all-issues
  report [ 0 0 0 0 0 ]
end

to-report mutation-condition
  report random-float 1.0 < mutation-rate
end
@#$#@#$#@
GRAPHICS-WINDOW
970
363
1122
516
-1
-1
14.4
1
10
1
1
1
0
0
0
1
0
9
0
9
0
0
1
ticks
30.0

BUTTON
4
10
67
43
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
148
10
211
43
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
70
10
145
43
go once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
228
15
320
48
rng-seed
rng-seed
0
10
3.0
1
1
NIL
HORIZONTAL

SLIDER
325
194
438
227
mutation-rate
mutation-rate
0
.5
0.1
.01
1
NIL
HORIZONTAL

SLIDER
666
21
765
54
IO-fixed-cost
IO-fixed-cost
0
100
0.0
1
1
NIL
HORIZONTAL

SLIDER
12
105
184
138
state-income
state-income
0
10
5.0
.1
1
NIL
HORIZONTAL

PLOT
10
386
218
506
IO net revenue
NIL
NIL
0.0
500.0
0.0
10.0
true
true
"" ""
PENS
"Net Revenue" 1.0 2 -16777216 true "" "plot IO-revenue - IO-operating-cost"
"Member Count" 1.0 0 -13345367 true "" "plot count members"
"0" 1.0 0 -2674135 true "" "plot 0"
"100" 1.0 0 -7500403 true "" "plot 100"
"Investment Costs" 1.0 2 -955883 true "" "plot issue-cost first IO-priorities"

PLOT
235
389
458
509
Member utility
NIL
NIL
0.0
500.0
0.0
10.0
true
true
"" ""
PENS
"Min utility" 1.0 2 -16777216 true "" "plot min [my-utility] of members"
"Max utility" 1.0 2 -7500403 true "" "plot max [my-utility] of members"
"Mean utility" 1.0 2 -2674135 true "" "plot mean [my-utility] of members"
"Median utility" 1.0 2 -955883 true "" "plot median [my-utility] of members"

CHOOSER
1023
79
1127
124
allocation-strategy
allocation-strategy
"first priority"
0

PLOT
471
388
725
508
Member contributions
NIL
NIL
0.0
10.0
0.0
5.0
true
true
"" ""
PENS
"Min Contribution" 1.0 2 -16777216 true "" "plot min [my-IO-contribution] of members"
"Max Contribution" 1.0 2 -7500403 true "" "plot max [my-IO-contribution] of members"
"Mean Contribution" 1.0 2 -2674135 true "" "plot mean [my-IO-contribution] of members"
"Median Contribution" 1.0 2 -955883 true "" "plot median [my-IO-contribution] of members"

PLOT
748
392
947
512
Member median priorities
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Security" 1.0 0 -16777216 true "" "plot median[ item 0 my-priorities  ] of members"
"Trade" 1.0 0 -7500403 true "" "plot median [ item 1 my-priorities ] of members"
"Human Rights" 1.0 0 -2674135 true "" "plot median[ item 2 my-priorities ] of members"
"Environment" 1.0 0 -955883 true "" "plot median[ item 3 my-priorities ] of members"
"Culture" 1.0 0 -6459832 true "" "plot median[ item 4 my-priorities ] of members"
"Expected Value" 1.0 0 -13840069 true "" "plot 20"
"15" 1.0 0 -13345367 true "" "plot 15"

SLIDER
672
85
844
118
min-contribution
min-contribution
0
5
2.0
.25
1
NIL
HORIZONTAL

CHOOSER
822
152
926
197
vote-type
vote-type
"plurality" "instant runoff"
1

SLIDER
10
188
141
221
state-type-fraction
state-type-fraction
0
1
0.85
.01
1
NIL
HORIZONTAL

SLIDER
8
145
206
178
inhibited-shadow-future
inhibited-shadow-future
0
1
0.85
.01
1
NIL
HORIZONTAL

SLIDER
257
148
434
181
uninhibited-offset
uninhibited-offset
-1
0
-0.4
.05
1
NIL
HORIZONTAL

SLIDER
1142
24
1267
57
benefit-multiplier
benefit-multiplier
0
5
3.6
.1
1
NIL
HORIZONTAL

SLIDER
972
21
1137
54
issue-cost-multiplier
issue-cost-multiplier
0
2
1.0
.1
1
NIL
HORIZONTAL

SLIDER
779
17
958
50
structure-cost-multiplier
structure-cost-multiplier
0
2
0.2
.1
1
NIL
HORIZONTAL

CHOOSER
163
186
312
231
optimization-resolution
optimization-resolution
1 0.5 0.1
2

SLIDER
825
224
968
257
catch-defection-rate
catch-defection-rate
0
1
0.5
.05
1
NIL
HORIZONTAL

SLIDER
978
225
1187
258
default-permitted-defections
default-permitted-defections
0
2
1.0
.5
1
NIL
HORIZONTAL

SLIDER
712
270
945
303
low-minimum-membership-priority
low-minimum-membership-priority
0
100
0.0
1
1
NIL
HORIZONTAL

CHOOSER
1047
162
1231
207
membership-priority-meta
membership-priority-meta
"always high" "always low" "higher beyond threshold" "lower beyond threshold"
1

SLIDER
623
227
807
260
membership-change-threshold
membership-change-threshold
0
100
20.0
1
1
NIL
HORIZONTAL

SLIDER
982
267
1188
300
priority-threshold-difference
priority-threshold-difference
0
30
15.0
1
1
NIL
HORIZONTAL

CHOOSER
559
10
651
55
initial-IO-wealth
initial-IO-wealth
1 100
0

CHOOSER
428
11
553
56
initial-membership-count
initial-membership-count
10 25 50 75 100
0

CHOOSER
330
10
426
55
simulation-length
simulation-length
500 1000 2000 4000
2

SLIDER
895
87
987
120
next-scope
next-scope
1
5
1.0
1
1
NIL
HORIZONTAL

CHOOSER
211
91
303
136
apply-rate
apply-rate
0.01 0.1 0.5 1
0

CHOOSER
940
157
1032
202
fraction-voting
fraction-voting
0.2 0.25 0.33 0.5 0.66 1
3

CHOOSER
669
145
807
190
priority-vote-rate
priority-vote-rate
1 5 10 50 100
2

@#$#@#$#@
## PURPOSE
This model is intended to explore the ways in which cooperation in international organizations changes as the preferences of the states that created the organization change. Because the possible changes are dependent upon both the states' internal decision making processes the nature of the cooperation problem, and the rules of the IO, it is quite easy to overcomplicate the model by trying to consider all the possible combinations of these factors. As such, this particular model is intended to provide an interface and outline than can be expanded upon for more specialized simulations as desired.


## ENTITIES,STATE VARIABLES, AND SCALES

ACTORS

The models consists of 100 states (turtles) laid out on a 10 x 10 grid. Each state is either a member of non-member of an international organization intended to facilitate cooperation on across several possible issues. All states have 100 points to be distributed across 5 possible areas of cooperation, with more points corresponding to a higher level of precendence. They also receive a set income each tick which can either be saved or invested in the IO to try to increase the state's utility. Currently, each state receives the same income per turn and consequently has the same potential to contribute to the organization.

The IO itself is represented by the observer. There are two main approaches to modeling the evolution of IOs: endogenous, where the rules are completely driven by the choices of the states, and exogenous, where the rules for the IO are explicitly controlled by the researcher. For reasons explained in the transition memo, this model focuses on the exogenous approach, and subdivides it into "static" cases where the rules do not change and "dynamic" cases where the IO is forced to evolve according to user-defined meta-rules.

## Process overview and scheduling

Each tick can be divided into four main phases: voting, planning, execution, and updating.

### VOTING
If voting is on, all votes occur here. Currently, the only fully implemented voting mechanism is the one to decide the issue area, but voting mechanisms for defection flexibility are also in development.

### PLANNING
In this stage, member states decide how much they will contribute to the IO.  For now, non-member states do not nothing in this stage.

### EXECUTION
Here, all member states pay their previously determined contributions to the IO. The IO catches some defectors according to the parameters that govern detection monitoring, and then allocates funds according to the IO spending submodel.

### UPDATING
In this stage, the IO first updates its records of income and expenses. Members can then use this information to update their beliefs about the utility of the IO and leave if they do not believe it is worth it to continue.
Similarly, non-members decide if they want to join the IO.

Finally, states mutate by chance by shifting some of their preference points from one issue to another. 

## INTERFACE
As you have probably noticed, this model has many sliders and choosers to control the state- and simulation-level parameters. I have tried to group them by general purpose (Initial conditions at the top center, state variables in the bottom left, and IO rules and meta-rules on the right) but these divisions are imperfect because I also tried to keep closely-related parameters together. Many of the numeric choosers could also be sliders, but I felt that limiting the number of possibilities helps reduce the temptation to overtest the parameter space. Unless otherwise specified, there are not yet any default values for the numeric parameters, so those may need to be established for more systematic experimentation.

### INITIAL CONDITIONS
These should be fairly straightforward.
**rng-seed** is explicit in order to replay interesting experiments.
 
**simulation-length** controls the number of simulation rounds.

**initial-IO-wealth** controls represents any resources the IO has at the beginning of the simulation period (because we are starting with an existent organization).

**issue-cost-type** and **IO-cost-type** control how the cooperation problem and structural costs of the IO scale, respectively.

**benefit-multiplier** controls how much the IO returns for investment in a given area once the cost-threshold is crossed


### STATE PARAMETERS
**state-income** is the total amount of "points" each state has at its disposable in a uniform distribution. If other distributions are added, it could potentially be modified to represent the mean or median income.

**min-contribution** if a state gets caught contributing less than this amount it counts as a full defection. Contributions between the minimum and expected contributions are treated as partial defections.

**apply-rate** is the rate at which non-members randomly apply for membership 

**inhibited-shadow-future, uninhibited-offset, and state-type-fraction** controls how negatively states think defecting in one turn will impact their ability to benefit from the IO in the future (because of punishments, other states diminishing contributions, the IO collapsing, etc..) the inhibited-shadow future controls the parameter for more cautious states. Uninhibited-offset is a negative factor that is combined to allow for more short-sighted/risk-taking states, and state-type-fraction controls the rate at which states are assigned to one of the two types when they join the IO.

**optimization-resolution** controls how finely divided the range of state contributions are. Lower resolutions increase the ability of states to maximize utility but also increase the amount of time for the calculation, so too fine of a grain can dramatically slow the simulation.

### IO Rules and Meta-Rules
**priority-vote-rate** is the number of ticks between votes on the next agenda

**alocation-strategy** how the IO uses its available fundss to address issues on the agenda. For now, the only option is to put everything toward the number one priority, but the chooser is still there for if other options are added later.

**next-scope** is the maximum number of issues the IO will try to tackle in the next session. Because of the default allocation strategy, it is best to keep simply this at 1 for now, but it can be altered mid-experiment if and once other allocation strategies are implemented to explore a new set of meta-rules.

**fraction-voting** is how much of the membership participates in votes.

**catch-defection-rate** governs how frequently the IO detects defection.

**membership-priority-meta** has the rules about when and how the IO changes its membership requirements For now, there are two static options and two dynamic options that change the requirements when the threshold is crossed.

**membership-change-threshold** is the trigger from the IO switching from one membership rule to another according to the meta-rule. For now, the threshold is based on the number of member states but other possible thresholds include net income and member defection rate. It is also conceivable to have multiple concurrent thresholds, but I did not find it necessary to include that for the conceptual demonstration.

**priority-threshold-difference** is how much higher the high priority requirement is than the lower one


## DESIGN CONCEPTS
BASIC PRINCIPLES

COLLECTIVES
The primary collective is the international organization, which consists of multiple states trying to increase cooperation in the issue area. For now, there is exactly one IO, but the model could theoretically be extended to consider multiple competing (or complementary) organizations.

EMERGENCE
Even when the IO starts off with a relatively heterogenous population and no membership restrictions, the traits of member states rapidly diverge from the general population due to strong self-selection.

SENSING
Member states receive payouts from the IO and could potentially reconstruct the aggregate totals because they know how many members there are and the IO's decision making process.
However, they explicitly DO NOT know the contributions, preferences, or beliefs of a given state at a given time.

LEARNING and PREDICTION

The current implementation of learning is intentionally extremely simple: states make a prediction about what the IO will do next turn based solely on the utility provided in the previous turn. They do not learn from the past beyond using the immediate previous turn to estimate how much other states will cooperate.


STOCHASTICITY
There are currently two main sources of stochasticity in the model: the initial distribution of preferences and the related mutation rate. 
More stochasticity is added by using random numbers to determine which non-members join, but this is not essential to the model and may eventually be replaced.


## INTITIALIZATION
All states are initialized with the same level of wealth and then a user defined number join the IO. The IO is also given a user defined starting budget.

## INPUT DATA
The model does not rely on external data.

## SUBMODELS

### VOTING
The IO updates its rules on by asking the states to vote according to the voting procedure(s) every time the number of ticks is evenly divisible by the voting rate.
In the latest version, an instant-runoff vote is used to pick the single most popular issue as the focus of the organization.

### DECIDING CONTRIBUTION
States try to maximize an expected utility function that considers both the immediate utility of a given contribution and its future repercussions.  The state then samples values from the curve at a specified interval and picks the highest one. We should be able to smoothen the process by finding and using a calculus library.

While the decision rules themselves are still being developed, they should consider how well the current IO's agenda matches their own preferences and how the structure of the IO and actions of other members have contributed to previous outcomes.

### IO SPENDING
After receiving all payments, the organization first pays its expenses, and then, if necessary,diverts some of the funds to its reserve, which is an emergency fund of sorts in case its income is ever insufficient. With the remaining funds, the IO begins to put money into different problems according to its investment strategy. Once again, there are currently two very basic distribution options ("everything goes to highest preference" and "evenly split between all issues on agenda"), but only the second is compatible with the updated instant-runoff voting procedure. If the amount put toward a given issue exceeds the minimum threshold, the invested amount is scaled by the multiplier and payed out to each state's reward fund for that issue. If not, the reward is 0. 
(Of course, a more robust allocation process might consider secondary issue areas with lower thresholds, but this is not a concern right now because all areas have the same costs.)

### MEMBER UTILITY
Currently, the utility  is captured 
((average of IO payouts * preference weights) - contribution) * 
((shadow of future) * (expected - contribution) / expected)
to produce a different quadratic curve for each state that is weighted by its preferences, degree of defection as well as a subjective perception of the risks of defection.

### LEAVING IO
Currently, there are two opportunities to leave the IO: the decide contribution step and the updating step. In both cases, this is a very simple comparison of the turns utility (expected in the first, actualy in the second) to the contribution, but the process can easily be adapted to consider other factors.

### JOINING IO
There are two steps to joining the IO. First, a non-member state has to apply, which is currently represented by a simple "wants to join" function. If desired, this can be expanded by adding in a delay period or fleshing out how non-member states derive utility outside the IO.
Once a state has decided it wants to join, the IO has to approve the application.


### MUTATION
A uniform random value generator determines whether a state will mutate this tick. If the state is selected to mutate, it shifts some of its points from one issue area to another.



## CREDITS AND REFERENCES
Rasul Dent
Peter Carey
Emily Ritter
- ROCCA lab
Last updated April 30, 2020
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
