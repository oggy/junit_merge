## JUnit Merge

Merges two or more JUnit XML reports, such that results from one run may
override those in the other. Reports may be single files or directory trees.

## Usage

Install:

    gem install junit_merge

Run:

    junit_merge SOURCE1.xml SOURCE2.xml ... TARGET.xml

Test results in SOURCE[1..n].xml will overwrite their counterparts in
TARGET.xml. Summary statistics will be updated as necessary. The sources and
target may be directories -- files at the same relative paths under each will be
merged (recursively).

## Why?

The intended use case is rerunning failures in CI.

Of course, your test suite *should* pass 100% of the time, be free from
nondeterminism, never modify global state, not rely on external services, and
all those good things.

But this is real life.

Sometimes you don't have a spare week to diagnose intermittent failures plaguing
your build. Or perhaps you're dealing with a legacy suite. Or you're relying on
tools which offer no synchronization mechanisms, making you resort to sleeps
which don't always suffice on a cheap, underpowered CI box. Or you're dealing
with an integration suite that legitmately hits some external service over a
flaky network connection.

This one's for you poor buggers. :beer:

## Example

Here's an example of how to set up an [RSpec][rspec] suite under
[Jenkins][jenkins].

First, we need to output the results to a file in JUnit format.

    rspec --format progress --format RspecJunitFormatter --out reports/rspec.xml spec

Next, we need to add options to dump the failed examples to a file. An easy way
is using [respec][respec]: simply change `rspec` to `respec`. Another option
is to use the failures logger in [parallel_tests][parallel-tests].

    respec --format progress --format RspecJunitFormatter --out reports/rspec.xml spec

Now, if the first build returns non-zero, we'll need to run just the
failures. With respec, we can use the `f` specifier. We should also output the
junit report to a different location:

    respec --format progress --format RspecJunitFormatter --out reports/rspec-rerun.xml f

Finally, if the rerun was required, we can merge the rerun results into the
original results:

    junit_merge reports/rspec-rerun.xml reports/rspec.xml

Putting it all together:

    #!/bin/sh -x

    status=0
    if ! respec --format progress --format RspecJunitFormatter --out reports/rspec.xml spec; then
      respec --format progress --format RspecJunitFormatter --out reports/rspec-rerun.xml f
      status=$?
      junit_merge reports/rspec-rerun.xml reports/rspec.xml
    fi
    exit $status

Note that if you don't specify the shebang, Jenkins will run your shell with
`-ex`, which will stop execution after the first build failure.

[rspec]: https://github.com/rspec/rspec
[jenkins]: http://jenkins-ci.org/
[respec]: https://github.com/oggy/respec
[parallel-tests]: https://github.com/grosser/parallel_tests

## Contributing

 * [Bug reports](https://github.com/oggy/junit_merge/issues)
 * [Source](https://github.com/oggy/junit_merge)
 * Patches: Fork on Github, send pull request.
   * Include tests where practical.
   * Leave the version alone, or bump it in a separate commit.

## Copyright

Copyright (c) George Ogata. See LICENSE for details.
