"""本地合成文档测试，覆盖实际CLI；不调用模型、不联网。"""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile
from xml.sax.saxutils import escape

SCRIPT = Path(__file__).with_name("check_manuscript.py")
spec = importlib.util.spec_from_file_location("check_manuscript", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def file(self, name, text):
        p = self.root / name
        p.write_text(text, encoding="utf-8")
        return p

    def test_numeric_clean(self):
        p = self.file("x.md", "正文[1-2]。\n## 参考文献\n[1] 资料甲\n[2] 资料乙\n")
        self.assertTrue(m.check(p)["ok"])
        self.assertEqual(m.check(p)["citation_keys"], 2)

    def test_missing_reference(self):
        p = self.file("x.txt", "正文[2]。\n参考文献\n[1] 资料甲\n")
        self.assertFalse(m.check(p)["ok"])

    def test_duplicate_reference(self):
        p = self.file("x.md", "正文[1]。\n参考文献\n[1] 资料甲\n[1] 资料乙\n")
        self.assertFalse(m.check(p)["ok"])

    def test_fence_and_links_not_citations(self):
        p = self.file("x.md", "正文[1]。\n[9](https://example.org)\n```txt\n[8]\n```\n参考文献\n[1] 资料甲\n")
        self.assertTrue(m.check(p)["ok"])

    def test_adjacent_numeric_citations(self):
        p = self.file('x.md', '正文[1][2]。\n参考文献\n[1] 资料甲\n[2] 资料乙')
        self.assertEqual(m.check(p)['citation_keys'], 2)

    def test_bad_range(self):
        p = self.file("x.md", "正文[2-1]。\n参考文献\n[1] 资料甲\n")
        self.assertFalse(m.check(p)["ok"])

    def test_unsupported_author_year(self):
        p = self.file("x.md", "正文(Author, 2020)。\nReferences\nAuthor (2020). Title.\n")
        self.assertEqual(m.check(p)["citation_check"], "not_covered")

    def bib(self):
        return self.file("x.bib", "@article{a,\n title={A}, author={Test}, year={2020}, doi={10.1234/abc}\n}\n")

    def test_tex_clean(self):
        p = self.file("x.tex", r"正文\citep[见][2]{a}。\label{fig:a}\ref{fig:a}")
        self.assertTrue(m.check(p, [self.bib()])["ok"])

    def test_tex_missing_key(self):
        p = self.file("x.tex", r"正文\cite{missing}")
        self.assertFalse(m.check(p, [self.bib()])["ok"])

    def test_tex_comments_ignored(self):
        p = self.file("x.tex", "% \\cite{missing}\n正文\\cite{a}")
        self.assertTrue(m.check(p, [self.bib()])["ok"])

    def test_missing_label(self):
        p = self.file("x.tex", r"正文\cite{a}\ref{missing}")
        self.assertFalse(m.check(p, [self.bib()])["ok"])

    def test_duplicate_label(self):
        p = self.file("x.tex", r"正文\label{x}\label{x}\ref{x}")
        self.assertFalse(m.check(p)["ok"])

    def test_duplicate_bib_key(self):
        p = self.file("x.tex", r"正文\cite{a}")
        b = self.bib()
        b.write_text(b.read_text() * 2)
        self.assertFalse(m.check(p, [b])["ok"])

    def test_duplicate_doi(self):
        p = self.file("x.tex", r"正文\cite{a,b}")
        b = self.bib()
        b.write_text(b.read_text() + b.read_text().replace("{a,", "{b,").replace("10.1234/abc", "https://doi.org/10.1234/ABC"))
        self.assertFalse(m.check(p, [b])["ok"])

    def test_tex_resources_warn_not_execute(self):
        p = self.file("x.tex", r"正文\input{/not/read}\write18{exit}")
        result = m.check(p)
        self.assertTrue(any("外部" in x for x in result["warnings"]))

    def docx(self, paras, comments=False):
        p = self.root / "x.docx"
        xml = '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
        xml += ''.join('<w:p><w:r><w:t>' + escape(x) + '</w:t></w:r></w:p>' for x in paras)
        xml += '</w:body></w:document>'
        with zipfile.ZipFile(p, 'w') as z:
            z.writestr('word/document.xml', xml)
            if comments:
                z.writestr('word/comments.xml', '<comments/>')
        return p

    def test_docx_clean(self):
        result = m.check(self.docx(['正文[1]。', '参考文献', '[1] 资料甲']))
        self.assertTrue(result['ok'])
        self.assertEqual(result['citation_check'], 'numeric_brackets')

    def test_docx_comments(self):
        result = m.check(self.docx(['正文'], comments=True))
        self.assertTrue(any('批注' in x for x in result['warnings']))

    def test_invalid_docx(self):
        p = self.file('bad.docx', 'not zip')
        with self.assertRaises(zipfile.BadZipFile):
            m.check(p)

    def test_anonymous(self):
        self.assertFalse(m.check(self.file('x.txt', '测试学校正文'), anonymous_terms=['测试学校'])['ok'])

    def test_empty(self):
        self.assertFalse(m.check(self.file('x.md', ''))['ok'])

    def test_images_missing_empty_remote(self):
        p = self.file('x.md', '正文\n![图](missing.png)')
        self.assertFalse(m.check(p)['ok'])
        self.file('empty.png', '')
        p.write_text('正文\n![图](empty.png)')
        self.assertFalse(m.check(p)['ok'])
        p.write_text('正文\n![图](https://example.org/figure.png)')
        self.assertTrue(any('外部' in x for x in m.check(p)['warnings']))

    def test_image_placeholder_blocks(self):
        p = self.file('x.md', '正文 [image_1_2]')
        self.assertFalse(m.check(p)['ok'])

    def test_docx_dtd_rejected(self):
        p = self.root / 'dtd.docx'
        with zipfile.ZipFile(p, 'w') as z:
            z.writestr('word/document.xml', '<!DOCTYPE x><x/>')
        with self.assertRaises(ValueError):
            m.check(p)

    def test_docx_expansion_limit(self):
        p = self.root / 'large.docx'
        with zipfile.ZipFile(p, 'w', compression=zipfile.ZIP_DEFLATED) as z:
            z.writestr('word/document.xml', 'a' * (m.MAX_BYTES + 1))
        with self.assertRaises(ValueError):
            m.check(p)

    def test_cli_readonly(self):
        for name, content, expected in [('ok.md', '正文[1]。\n参考文献\n[1] 资料', 0),
                                         ('bad.md', '正文[2]。\n参考文献\n[1] 资料', 1),
                                         ('bad.docx', 'broken', 2)]:
            p = self.file(name, content)
            before = p.read_bytes()
            result = subprocess.run([sys.executable, '-B', '-I', str(SCRIPT), str(p)], capture_output=True, text=True)
            self.assertEqual(result.returncode, expected, result.stderr + result.stdout)
            self.assertIsInstance(json.loads(result.stdout), dict)
            self.assertEqual(p.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
