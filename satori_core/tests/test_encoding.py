"""Ourin-authored regressions for the POSIX CP932 boundary and real helper."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class EncodingTests(unittest.TestCase):
    def test_bom_signature_and_strict_conversion(self):
        compiler = shutil.which('clang++')
        if not compiler:
            self.skipTest('clang++ unavailable')
        with tempfile.TemporaryDirectory(prefix='ourin-satori-encoding-') as tmp:
            folder = Path(tmp)
            source = folder / 'main.cpp'
            source.write_text(r'''
#include <string>
#include <stdexcept>
std::string UTF8toSJIS(const std::string&);
std::string SJIStoUTF8(const std::string&);
int main() {
    const std::string plain = u8"＊OnBoot\nこんにちは\n";
    if (UTF8toSJIS("\xEF\xBB\xBF" + plain) != UTF8toSJIS(plain)) return 1;
    if (!UTF8toSJIS("\xEF\xBB\xBF").empty()) return 2;
    if (UTF8toSJIS("") != "" || UTF8toSJIS("a") != "a") return 3;
    if (SJIStoUTF8(UTF8toSJIS(plain)) != plain) return 4;
    if (UTF8toSJIS("a\xEF\xBB\xBF") != "a ") return 5;
    if (UTF8toSJIS(u8"x噓y") != "x y") return 8;
    try { UTF8toSJIS("\xED\xA0\x80"); return 9; } catch (const std::runtime_error&) {}
    try { UTF8toSJIS("\xEF\xBB"); return 6; } catch (const std::runtime_error&) {}
    try { UTF8toSJIS("\xFF"); return 7; } catch (const std::runtime_error&) {}
    return 0;
}
''')
            binary = folder / 'encoding-test'
            subprocess.run([compiler, '-std=c++17', str(source), str(ROOT/'src/EncodingIconv.cpp'), '-liconv', '-o', str(binary)], check=True, capture_output=True, timeout=60)
            subprocess.run([str(binary)], check=True, capture_output=True, timeout=10)

    def test_real_helper_utf8_bom_dictionary_lifecycle(self):
        helper = ROOT / 'build/satori_core'
        if not helper.is_file():
            self.skipTest('satori_core not built')
        with tempfile.TemporaryDirectory(prefix='ourin-satori-bom-') as tmp:
            root = Path(tmp)
            (root/'satori_bootconf.txt').write_text('is_utf8_all,1\n')
            dictionary = root/'dic01.txt'
            dictionary.write_bytes(b'\xef\xbb\xbf' + '＊OnBoot\nこんにちは\n\n＊OnMouseDoubleClick\t１\n会話です\n\n＊OnClose\nさようなら\n'.encode())
            original = hashlib.sha256(dictionary.read_bytes()).digest()
            messages = [{'cmd':'load','ghost_root':str(root)}, *[{'cmd':'request','id':event} for event in ('OnBoot','OnMouseDoubleClick','OnClose')], {'cmd':'unload'}]
            result = subprocess.run([str(helper)], input=''.join(json.dumps(x)+'\n' for x in messages).encode(), capture_output=True, cwd=root, timeout=20)
            self.assertEqual(result.returncode, 0)
            answers = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(len(answers), 5)
            self.assertTrue(all(x['ok'] for x in answers))
            self.assertIn('会話です', answers[2]['value'])
            self.assertIn(b'selecting', result.stderr)
            self.assertNotIn(b'selecting', result.stdout)
            self.assertEqual(hashlib.sha256(dictionary.read_bytes()).digest(), original)


if __name__ == '__main__':
    unittest.main()
