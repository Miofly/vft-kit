import pathlib
import unittest


SKILL_FILE = pathlib.Path(__file__).parents[1] / "SKILL.md"


def read_frontmatter():
    content = SKILL_FILE.read_text(encoding="utf-8")
    if not content.startswith("---\n"):
        raise AssertionError("SKILL.md must start with YAML frontmatter")

    lines = content.splitlines()
    closing_index = next(
        (index for index, line in enumerate(lines[1:], start=1) if line == "---"),
        None,
    )
    if closing_index is None:
        raise AssertionError("SKILL.md frontmatter must have a closing --- line")

    keys = []
    for line in lines[1:closing_index]:
        if not line.strip() or line[0].isspace() or line.startswith("#"):
            continue
        if ":" not in line:
            raise AssertionError(
                f"Invalid top-level SKILL.md frontmatter line: {line!r}"
            )
        keys.append(line.split(":", 1)[0])

    return content, keys


class SkillMetadataTests(unittest.TestCase):
    def test_frontmatter_uses_only_cross_client_fields(self):
        _, keys = read_frontmatter()
        self.assertEqual(["name", "description"], keys)

    def test_active_skill_does_not_reference_legacy_name(self):
        content, _ = read_frontmatter()
        self.assertNotIn("co-work-report", content)


if __name__ == "__main__":
    unittest.main()
