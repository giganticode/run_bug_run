# RunBugRun
<p align="center">
  <img src="docs/logo.png">
</p>

> [!NOTE]  
> This is the revised and extended version of RunBugRun. The older version can be found in the `legacy` branch.

## What is RunBugRun

RunBugRun is an [APR](http://program-repair.org/) dataset of over 700'000 executable buggy/fixed pairs of short programs taken from [IBM Project CodeNet](https://github.com/IBM/Project_CodeNet) written in 9 languages (C++, C, Python, Java, Ruby, JavaScript, Go, PHP, C#).

It can be used to evaluate APR tools, that is, tools that automatically find and repair bugs in source code.

RunBugRun comes with tests, bug labels and infrastructure to execute programs. In order to warrant safe execution it uses [Bubblewrap](https://github.com/containers/bubblewrap) as a sandbox.

RunBugRun has pre-defined training, validation and test sets. APR tools can use the training set as they please. For evaluation, they are given a test set of buggy programs that do not pass all tests. A tool's performance is measured as the percentage of programs that the tool can fix in such a way that it passes all tests.


# Obtaining the Dataset

RunBugRun is distributed as a lrzip-compressed SQLite3 database dump. After downloading the compressed dump (see Releases page of this project) the following steps are necessary to restore the database.

### Install lrzip and sqlite

```bash
sudo apt-get install lrzip sqlite3
```

### Decompress

```bash
lrunzip -z runbugrun.sql.lrz
```

### Restore

```bash
sqlite3 runbugrun.db < runbugrun.sql
```

# Data Sources

RunBugRun is a curated collection of data.
We used the following sources. For terms of use/license information please consult the corresponding project/website.

| Source | URL | Data |
|--------|------|--------|
| IBM CodeNet|  https://github.com/IBM/Project_CodeNet | Code submissions |
| AlphaCode/CodeContests | https://github.com/google-deepmind/code_contests | Tests |
| AtCoder | https://atcoder.jp/posts/21 | Tests |
| PIE4Perf |  https://github.com/madaan/pie-perf| Problem description translations (e.g., Japanese to English) |

# Database Schema Documentation

RunBugRun is distributed as a SQLite database, containing code, tests and metadata. It contains the following tables:

## `tests`
Stores test cases.

| Column | Type | Description |
|--------|------------|-------------|
| `id` | integer | Primary key |
| `problem_id` | varchar | Reference to `problems.problem_id` |
| `test_id` | integer | Test identifier |
| `input` | text | Test input  |
| `output` | text | Expected output  |
| `created_at` | datetime(6) | Creation timestamp |
| `updated_at` | datetime(6) | Last update timestamp |
| `origin` | integer | Origin of the test (0: unknown, 1: codenet, 2: manual, 3: alphacode, 4: atcoder) (default: 0) |
| `active` | boolean | Whether test is active (default: true) |

## `problems`
Stores problem descriptions.

| Column | Type | Description |
|--------|--------|-------------|
| `id` | integer | Primary key |
| `problem_id` | varchar | IBM CodeNet problem identifier  |
| `text` | text | Problem description  |
| `similar_problems` | jsonb | JSON array of similar problems  |

## `bugs`
Stores bugs (full code).

| Column | Type | Description |
|--------|------------|-------------|
| `id` | integer | Primary key |
| `buggy_code` | text | The buggy code |
| `fixed_code` | text | The fixed code |
| `problem_id` | varchar | Reference to `problems.problem_id` |
| `user_id` | varchar | ID of user who `submitted` |
| `buggy_submission_id` | varchar | ID of buggy submission (IBM CodeNet ID) |
| `fixed_submission_id` | varchar | ID of fixed submission (IBM CodeNet ID) |
| `language` | integer | Programming language (0: c, 1: cpp, 2: javascript, 3: java, 4: ruby, 5: python, 6: php, 7: go, 8: c_sharp) |
| `label_ids` | json | JSON array of label IDs  |
| `runtime_errors` | json | Runtime errors  |
| `change_count` | integer | Number of changes  |
| `split` | integer | Data split (0: train, 1: valid, 2: test, 3: unfiltered)  |
| `buggy_main_class` | varchar | Main class for buggy code (Java only) |
| `fixed_main_class` | varchar | Main class for fixed code (Java only) |
| `created_at` | datetime(6) | Creation timestamp |
| `updated_at` | datetime(6) | Last update timestamp |
| `token_count` | integer | Number of tokens  |
| `active` | boolean | Whether bug is active (default: true) |
| `hunk_count` | integer | Number of hunks  |
| `buggy_locs` | integer | Number of lines of code in the buggy version (logical)  |
| `fixed_locs` | integer | Number of lines of code in the fixed version (logical)  |


## `evaluations`
Tracks evaluation runs (initially empty).

| Column | Type | Description |
|--------|------------|-------------|
| `id` | integer | Primary key |
| `name` | varchar | Name of the evaluation |
| `started_at` | datetime(6) | When the evaluation started |
| `ended_at` | datetime(6) | When the evaluation ended  |
| `created_at` | datetime(6) | Creation timestamp |
| `updated_at` | datetime(6) | Last update timestamp |

## `runs`
Records individual test runs (initially empty).

| Column | Type | Description |
|--------|------------|-------------|
| `id` | integer | Primary key |
| `evaluation_id` | integer | Reference to `evaluations.id` |
| `status` | integer | Status of the run (0: pass, 1: fail, 2: error, 3: timeout, 4: compilation_error) |
| `bug_id` | integer | Reference to `bugs.id` |
| `bug_version` | integer | Version of the bug (0: buggy, 1: fixed, 2: candidate) |
| `bug_variant` | integer | Variant of the bug (0: default) |
| `candidate_index` | integer | Index of candidate  |
| `test_id` | integer | Reference to tests.id |
| `error_output` | text | Error output if any  |
| `output` | text | Program output  |
| `created_at` | datetime(6) | Creation timestamp |
| `updated_at` | datetime(6) | Last update timestamp |
| `wall_time` | decimal | Execution time in seconds  |