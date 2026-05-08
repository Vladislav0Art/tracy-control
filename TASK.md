
YOUR SETTING:
You are given two repositories:

1. Tracy: AI Tracing Kotlin library
2. API Coverage Evaluator: Evaluator that calculates how many API routes and attributes were covered by Tracy and builds evaluation reports over this information.

Your main task is to introduce modifications, new functionality, or/and enhancements to the existing Tracy code to maximize the evaluation score.


MODIFICATIONS LOOP:
Publish Tracy into local Maven → Run evaluator over published Tracy sources to compute the coverage with an evaluation report → analyze the report, identify areas for improvement in Tracy → proceed to the modifying Tracy sources → once finished with an incremental change, repeat the loop.


PRELIMINARY STEPS:
1. Set up both repositories and ensure you understand how to run tests (mainly, for Tracy) and run evaluator.
1. Next, you MUST understand how to run the evaluator over Tracy sources to compute the coverage. Steps you need to take:
   1. Publish Tracy as a library locally via Gradle's task Local Publish Maven.
   1. Then, feed the generated library sources into the evaluator.
   1. Once you generated the coverage report, you can analyze it, identify areas for improvement in Tracy, and proceed to the modifying Tracy sources to improve the score for the next generation.

Checkout from the main branch into a new branch in which you will implement all the modifications you plan to apply during the entire generation session. In other words, you commit all your changes in a single branch (splitting changes across different commits is for your choice).

NOTES:
1. You can use git commands to create branches, commit/revert changes and view the history of modifications in the Tracy repository.
1. You CANNOT use git to push the implemented modifications yourself, only creating commits/branches.
1. Install any missing dependencies/components you need to run the evaluator, build Tracy or run Tracy tests, etc (FYI, Python and JDK-21 are already installed).

FINISH CONDITIONS:
Finish the execution in one of the following conditions:
1. You realize that either the score reached its max value or the evaluation fit a plato with no significant score improvements between your attempts.
1. When you decide that introduced changes already represent HIGH quality implementation of new functionality and enhancements to the existing ones (usually this will be somewhere near the plato state).

BIDGET:
You have a defined budget for the evaluation:
1. Max turns: 350
2. Max Budget: $500

