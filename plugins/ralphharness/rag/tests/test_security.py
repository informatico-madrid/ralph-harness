"""Unit tests for SecurityLayer."""

from plugins.ralphharness.rag.security import SecurityLayer


class TestSecurityLayerRejects:
    def test_aws_key(self, sample_secret_chunk) -> None:
        result = SecurityLayer().sanitize(sample_secret_chunk)
        assert result.accepted is False
        assert result.rejected_by != ""

    def test_ssh_key(self) -> None:
        from plugins.ralphharness.rag.types import Chunk

        c = Chunk(
            content="-----BEGIN RSA PRIVATE KEY-----",
            source_path="test",
            spec_name="test",
        )
        assert SecurityLayer().sanitize(c).accepted is False

    def test_bearer_token(self) -> None:
        from plugins.ralphharness.rag.types import Chunk

        c = Chunk(
            content="Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
            source_path="test",
            spec_name="test",
        )
        assert SecurityLayer().sanitize(c).accepted is False

    def test_github_pat(self) -> None:
        from plugins.ralphharness.rag.types import Chunk

        # ghp_ + exactly 36 chars = 40 total
        c = Chunk(
            content="ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij",
            source_path="test",
            spec_name="test",
        )
        assert SecurityLayer().sanitize(c).accepted is False


class TestSecurityLayerAccepts:
    def test_clean_content(self, sample_chunk) -> None:
        result = SecurityLayer().sanitize(sample_chunk)
        assert result.accepted is True

    def test_code_comment_with_word_password(self) -> None:
        """A password variable assignment with short value should NOT trigger."""
        from plugins.ralphharness.rag.types import Chunk

        c = Chunk(
            content="# set_password is a common function name",
            source_path="test",
            spec_name="test",
        )
        result = SecurityLayer().sanitize(c)
        assert result.accepted is True
