TESTS = bin/test-wait-for.sh tests/test-session-start.sh tests/test-json.sh \
        tests/test-launch-check.sh tests/test-codex-run.sh

.PHONY: test
test:
	@set -e; for t in $(TESTS); do echo "== $$t"; sh $$t; done; echo "all tests passed"
