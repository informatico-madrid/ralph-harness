"""Unit tests for OnboardingStep framework."""

from __future__ import annotations


class TestOnboardingStep:
    def test_framework_exists(self) -> None:
        """OnboardingStep is importable (Phase 4 complete)."""
        from plugins.ralphharness.rag.onboarding import OnboardingStep

        assert OnboardingStep is not None
