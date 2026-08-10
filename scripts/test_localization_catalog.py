import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = REPO_ROOT / "Metrilens"
CATALOG_PATH = SOURCE_ROOT / "Localization" / "AppLocalization.swift"
KEY_PATTERN = re.compile(r'^\s*"([^"\\]*(?:\\.[^"\\]*)*)"\s*:', re.MULTILINE)
USAGE_PATTERN = re.compile(r'\.localized\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"')
STRING_LITERAL_PATTERN = re.compile(r'"(?:\\.|[^"\\])*"')
CHINESE_PATTERN = re.compile(r"[\u3400-\u9fff]")


def dictionary_keys(source: str, declaration: str) -> list[str]:
    start = source.index(declaration)
    assignment = source.index("=", start)
    opening = source.index("[", assignment)
    depth = 0
    for index in range(opening, len(source)):
        character = source[index]
        if character == "[":
            depth += 1
        elif character == "]":
            depth -= 1
            if depth == 0:
                return KEY_PATTERN.findall(source[opening + 1:index])
    raise AssertionError(f"Unterminated dictionary: {declaration}")


class LocalizationCatalogTests(unittest.TestCase):
    def test_every_usage_has_one_catalog_entry(self) -> None:
        catalog_source = CATALOG_PATH.read_text(encoding="utf-8")
        catalog_keys = dictionary_keys(
            catalog_source,
            "private static let chineseTranslations",
        )
        override_keys = dictionary_keys(
            catalog_source,
            "private static let englishOverrides",
        )

        self.assertEqual(len(catalog_keys), len(set(catalog_keys)))
        self.assertEqual(len(override_keys), len(set(override_keys)))
        self.assertTrue(set(override_keys).issubset(set(catalog_keys)))

        used_keys: set[str] = set()
        for path in SOURCE_ROOT.rglob("*.swift"):
            source = path.read_text(encoding="utf-8")
            if path != CATALOG_PATH:
                self.assertNotIn(".text(", source, path)
                hardcoded_chinese = [
                    literal
                    for literal in STRING_LITERAL_PATTERN.findall(source)
                    if CHINESE_PATTERN.search(literal)
                ]
                self.assertEqual(hardcoded_chinese, [], path)
            used_keys.update(USAGE_PATTERN.findall(source))

        self.assertEqual(set(catalog_keys), used_keys)


if __name__ == "__main__":
    unittest.main()
