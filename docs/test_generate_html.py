import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).parent))
import generate_html


class GenerateHTMLLinkTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.docs_dir = self.root / "docs"
        self.output_dir = self.docs_dir / "html"
        self.output_dir.mkdir(parents=True)

        self.source = self.docs_dir / "README_ja-jp.md"
        self.japanese = self.docs_dir / "ONBOARDING_ja-jp.md"
        self.english = self.docs_dir / "ONBOARDING_en-us.md"
        self.legacy_alias = self.docs_dir / "SSTP_Host_Modules_JA_ja-jp.md"
        self.manifest = self.docs_dir / "TRANSLATION_MANIFEST.md"
        self.project_readme = self.root / "README.md"
        self.index = self.output_dir / "index.html"
        for path in (
            self.source,
            self.japanese,
            self.english,
            self.legacy_alias,
            self.manifest,
            self.project_readme,
            self.index,
        ):
            path.touch()

        self.markdown_index = generate_html.build_markdown_index(
            [self.source, self.japanese, self.english, self.legacy_alias]
        )
        self.generated_outputs = {
            path.resolve(): generate_html.get_output_filename(path)
            for path in (self.source, self.japanese, self.english, self.legacy_alias)
        }

    def tearDown(self):
        self.temp_dir.cleanup()

    def rewrite(self, body):
        return generate_html.rewrite_local_links(
            body,
            self.source,
            "ja-jp",
            self.markdown_index,
            self.generated_outputs,
            self.output_dir,
        )

    def test_language_neutral_markdown_link_uses_current_language(self):
        body = '<a href="ONBOARDING.md#start">guide</a>'
        rewritten = self.rewrite(body)
        self.assertIn('href="ONBOARDING_ja-jp.html#start"', rewritten)

    def test_markdown_link_outside_docs_keeps_existing_relative_file(self):
        body = '<a href="../README.md">project</a>'
        rewritten = self.rewrite(body)
        self.assertIn('href="../../README.md"', rewritten)

    def test_existing_html_and_excluded_markdown_are_rebased(self):
        body = (
            '<a href="html/index.html">index</a>'
            '<a href="TRANSLATION_MANIFEST.md">manifest</a>'
        )
        rewritten = self.rewrite(body)
        self.assertIn('href="index.html"', rewritten)
        self.assertIn('href="../TRANSLATION_MANIFEST.md"', rewritten)

    def test_legacy_language_alias_can_keep_the_alias_in_the_source_name(self):
        body = '<a href="SSTP_Host_Modules_JA.md">host modules</a>'
        rewritten = self.rewrite(body)
        self.assertIn('href="SSTP_Host_Modules_JA_ja-jp.html"', rewritten)

    def test_external_and_fragment_links_are_unchanged(self):
        body = (
            '<a href="https://example.com/spec">external</a>'
            '<a href="#section">section</a>'
        )
        self.assertEqual(body, self.rewrite(body))


if __name__ == "__main__":
    unittest.main()
