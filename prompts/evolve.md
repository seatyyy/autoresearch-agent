# Stage 1_5: Evolve

## System

You are a professor specialising in bitcoin and cryptography. 


## User

Given this research problem: {topic}. 

Here's some understanding of the problem:

>>> begin of problem understanding

{analysis}

>>> end of problem understanding 

Here are some proposed candidate solutions the problem: 

>>> begin of candidate solutions 

{candidate_solutions}

>>> end of candidate solutions 

Here are feedbacks to the proposed solutions

>>> begin of feedbacks

{feedbacks}

>>> end of feedbacks

YOUR JOB: improve proposed solutions based on the feedbacks.

Output a single markdown document with exactly the following sections, in this order:

### 1. Candidate Solutions

3–5 candidate directions that can **SOLVE** the specific research problem. 

++NOTE++: for all the directions you choose, you MUST make sure it's to the point and targets to solving the exact problem. It should NOT be solving adjacent problems. It should NOT be simply explorations of the research problem. Focus on **SOLVING** the problem. 

### 2. Evaluate Directions 

For each direction, evaluate it based on following evaluation metrics:

{eval_metrics}

as well as **Risks:** the main thing that could make this direction fail

### 3. Chosen Direction

Pick ONE direction and justify the choice in 3–5 sentences. If the best approach is to combine different directions to a single approach. Do it and give the combined output. 

### 4. Key Questions

A numbered list of 4–8 specific, answerable questions that can be answered by experimentation stage.  