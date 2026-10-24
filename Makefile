TESTS = bin/test-wait-for.sh tests/test-session-start.sh tests/test-json.sh \
        tests/test-launch-check.sh tests/test-coordinator-log.sh tests/test-report-lead.sh tests/test-start-check.sh tests/test-rules-check.sh tests/test-start-result.sh tests/test-codex-run.sh tests/test-designer-run.sh tests/test-design-share.sh tests/test-public-text.sh \
        tests/test-docs-check.sh tests/test-board-drift.sh tests/test-board-set.sh

.PHONY: test
test:
	@set -e; for t in $(TESTS); do echo "== $$t"; sh $$t; done; echo "all tests passed"
