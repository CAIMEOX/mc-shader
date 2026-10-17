"""Verify generated Unicode fixtures independently of the system code page."""

import io
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from scripts.verify.reference import build, fixtures


class FixtureEncodingTest(unittest.TestCase):
    def test_fixtures_with_gbk_default(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "model").mkdir()
            (root / "build").mkdir()
            config = {"chat_template": "前{{ messages[0].content }}后"}
            (root / "model/tokenizer_config.json").write_bytes(
                json.dumps(config, ensure_ascii=False).encode("utf-8")
            )
            tokenizer = SimpleNamespace(
                encode=lambda text, **_: SimpleNamespace(ids=list(map(ord, text))),
                decode=lambda ids, **_: "".join(map(chr, ids)),
            )

            def reference(command, **_):
                Path(command[-1]).write_bytes(
                    json.dumps({"generated": [ord("二")]}).encode("utf-8")
                )

            def default_encoding(encoding=None, stacklevel=2):
                return "gbk" if encoding in (None, "locale") else encoding

            with (
                patch.object(fixtures, "ROOT", root),
                patch.object(build, "build", return_value=root / "reference"),
                patch.object(fixtures, "Tokenizer") as factory,
                patch.object(fixtures.subprocess, "run", side_effect=reference),
                patch("io.text_encoding", side_effect=default_encoding),
                patch("sys.stdout", new=io.StringIO()),
            ):
                factory.from_file.return_value = tokenizer
                fixtures.main()
            output = root / "build/reference"
            chat = json.loads((output / "chat.json").read_bytes())
            samples = json.loads((output / "fixtures.json").read_bytes())
            self.assertEqual(chat, {"prefix": "前", "suffix": "后"})
            self.assertEqual(samples[3]["prompt"], "Cafe\u0301 and 각")
            self.assertEqual(samples[1]["decoded"], "二")
            self.assertEqual(
                samples[3]["token_ids"], list(map(ord, "前Cafe\u0301 and 각后"))
            )


if __name__ == "__main__":
    unittest.main()
