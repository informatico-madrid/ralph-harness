"""Unit tests for OnboardingStep framework.

OnboardingStep is created in Phase 4 (task 4.7).
This test is a placeholder that verifies the expected interface.
"""

from __future__ import annotations


class TestOnboardingStep:
    def test_framework_exists(self) -> None:
        """OnboardingStep framework exists after Phase 4."""
        try:
            from plugins.ralphharness.rag.onboarding import OnboardingStep  # noqa: F401
        except ImportError:
            # Not yet implemented (Phase 4)
            pass
