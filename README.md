# RunBugRun
<p align="center">
  <img src="docs/logo.png">
</p>

## What is RunBugRun

RunBugRun is an [APR](http://program-repair.org/) dataset of ~450'000 executable buggy/fixed pairs of short programs taken from [IBM Project CodeNet](https://github.com/IBM/Project_CodeNet) written in 8 languages (C++, C, Python, Java, Ruby, JavaScript, Go, PHP).

It can be used to evaluate APR tools, that is, tools that automatically find and repair bugs in source code.

RunBugRun comes with tests, bug labels and infrastructure to execute programs. In order to warrant safe execution it uses [Bubblewrap](https://github.com/containers/bubblewrap) as a sandbox.

RunBugRun has pre-defined training, validation and test sets. APR tools can use the training set as they please. For evaluation, they are given a test set of buggy programs that do not pass all tests. A tool's performance is measured as the percentage of programs that the tool can fix in such a way that it passes all tests.

## Installation

### Data
RunBugRun's data can be downloaded in the form of gzipped JSONL files from [here](https://github.com/giganticode/run_bug_run_data) or downloaded directly with the `rbugr` utility.

### `rbugr`

As of today, we only support Ubuntu 22.04. For other distributions, please open an issue.
The `rbugr` utility is written in Ruby.
You'll need a recent version of Ruby (3.1) on your system (installed e.g. through [`rbenv`](https://github.com/rbenv/rbenv)).
In addition to a Ruby to run the utility, you'll need a Ruby to run Ruby submission programs. Here version 3.0, the version packaged by Ubuntu, is sufficient.

#### Prerequisities
Use the following to install the compilers/interpreters needed to run submission programs:
```
$ apt-get install php-cli nodejs gcc g++ default-jdk ruby python3 golang-go bubblewrap
```

#### Installation
In order to install the utility itself do:
```
$ git clone https://github.com/giganticode/run_bug_run.git
$ cd https://github.com/giganticode/run_bug_run.git
$ gem install bundler
$ bundle install
```

## Usage

### Download data

The `rbugr` helper utility can be used to manage dataset versions, obtain information on bugs, run bugs or evaluate the entire test set. 
To download the RunBugRun data at a particular version use:

```
$ bundle exec rbugr download 0.0.1
```

### Sanity Check

It is advised to do a sanity check of your setup by evaluating the *fixed* program versions.
```
$ bundle exec rbugr eval --fixed --output-filename=sanity_check.json.gz
```

### Showing Bug Information

To show information on a particular bug
use

`$ bundle exec rbugr bugs show BUG_ID`

For instance:

`$ bundle exec rbugr bugs show 4229`

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

`$ bundle exec rbugr bugs diff 42290`

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

`$ bundle exec rbugr eval PATH_TO_OUTPUT --output-filename=PATH_TO_EVAL_FILE`

where `PATH_TO_OUTPUT` should point to your tool's output file. This file should be a JSON**L** file in the following format:

```
{id: BUG_ID, preds: [FIX_CANDIDATE_CODE1, FIX_CANDIDATE_CODE2, ...]}
...
```

### Analysis of Evaluation

Once evaluated you can use `rbugr analyze` to calculate various evaluation metrics.
For instance:
```
$ bundle exec rbugr analyze PATH_TO_EVAL_FILE
```
You can use `--by-language` to get a per-language break-down of performance.

