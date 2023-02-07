# RunBugRun
<p align="center">
  <img src="docs/logo.png">
</p>


> **Warning**
> RunBugRun is in an early stage. The full code and data will follow in the next weeks

## What is RunBugRun

RunBugRun is an [APR](http://program-repair.org/) dataset of ~450'000 executable buggy/fixed pairs of short programs taken from [IBM Project CodeNet](https://github.com/IBM/Project_CodeNet) written in 8 languages (C++, C, Python, Java, Ruby, JavaScript, Go, PHP).

It can be used to evaluate APR tools, that is, tools that automatically find and repair bugs in source code.

RunBugRun comes with tests, bug labels and infrastructure to execute programs. In order to warrant safe execution it uses [Bubblewrap](https://github.com/containers/bubblewrap) as a sandbox.

RunBugRun has pre-defined training, validation and test sets. APR tools can use the training set as they please. For evaluation, they are given a test set of buggy programs that do not pass all tests. A tool's performance is measured as the percentage of programs that the tool can fix in such a way that it passes all tests.

## Installation

### Data
RunBugRun's data can be downloaded in the form of gzipped JSONL files (**links will follow**). However, we strongly recommend to use the corresponding infrastructure (see below).

### Infrastructure

RunBugRun's infrastructure is written in Ruby and can be installed as a RubyGem (**Note:** Gem has not yet published).

The gem can be installed using:

`$ gem install run_bug_run`

## Usage

### Download data

The `rbugr` helper utility can be used to manage dataset versions, obtain information on bugs, run bugs or evaluate the entire test set. 

To download the RunBugRun data at a particular version use:

`$ rbugr download 0.0.1`

### Showing Bug Information

To show information on a particular bug
use

`$ rbugr bugs show BUG_ID`

For instance:

`$ rbugr bugs show 4229`

will give:
<pre>{
  &quot;id&quot;: 4299,
  &quot;language&quot;: &quot;ruby&quot;,
  &quot;problem_id&quot;: &quot;p00000&quot;,
  &quot;change_count&quot;: 1,
  &quot;labels&quot;: [
    &quot;call.function.change&quot;,
    &quot;io.output.change&quot;
  ]
}
</pre>

### Printing a Diff

`$ rbugr bugs diff 42290`

<pre> #include &lt;bits/stdc++.h&gt;
 
 using namespace std;
 
 #define int long long
 #define N 100005
 
 int n, m, a, b, c, cnt = 0, from[N], to[N], f, t, s = 1, e = 1;
 int ans = 0;
 
 signed main() {
   ios_base::sync_with_stdio(0);
   cin &gt;&gt; n &gt;&gt; m;
   cin &gt;&gt; t;
   for (int i = 1; i &lt; m; ++i) {
     f = t;
     cin &gt;&gt; t;
     from[i] = min(f, t);
     to[i] = max(f, t);
   }
<font color="#CC0000">-  sort(from + 1, from + m - 1);</font>
<font color="#CC0000">-  sort(to + 1, to + m - 1);</font>
<font color="#4E9A06">+  sort(from + 1, from + m);</font>
<font color="#4E9A06">+  sort(to + 1, to + m);</font>
   for (int i = 1; i &lt; n; ++i) {
     cin &gt;&gt; a &gt;&gt; b &gt;&gt; c;
     while (i == from[s]) {
       cnt++;
       s++;
     }
     while (i == to[e]) {
       cnt--;
       e++;
     }
     ans += min(a * cnt, c + b * cnt);
   }
<font color="#4E9A06">+</font>
   cout &lt;&lt; ans &lt;&lt; &quot;\n&quot;;
 }
</pre>

### Evaluation

In order to evaluate your tool's output use the following

`$ rbugr eval PATH_TO_OUTPUT`

where `PATH_TO_OUTPUT` should point to your tool's output file. This file should be a JSON**L** file in the following format:

```
{id: BUG_ID, preds: [FIX_CANDIDATE_CODE1, FIX_CANDIDATE_CODE2, ...]}
...



```