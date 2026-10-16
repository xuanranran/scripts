"""Offline regression checks. Never run sysupgrade or contact GitHub."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("BASH", shutil.which("bash") or "bash")
PLATFORMS = ("rockchip", "x86")


class UpdaterTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="openwrt-tests-")
        self.addCleanup(self.directory.cleanup)
        self.work = Path(self.directory.name)
        self.env = dict(os.environ, FIXTURES=self.work.as_posix())
        self.libraries = {}
        for platform in PLATFORMS:
            source = (ROOT / f"update_openwrt_{platform}.sh").read_text(encoding="utf-8")
            # Load only definitions, before root checks and the live upgrade flow.
            source = source.split('if [[ $(id -u) != 0 ]]; then', 1)[0]
            library = self.work / f"{platform}.sh"
            library.write_text(source, encoding="utf-8", newline="\n")
            self.libraries[platform] = library

    def run_shell(self, platform, code, answers="", expected=0):
        script = 'source "$TEST_LIBRARY"\nset -euo pipefail\n' + code
        env = dict(self.env, TEST_LIBRARY=self.libraries[platform].as_posix())
        # Keep LF input on Windows; text mode would send h\r instead of h.
        result = subprocess.run([BASH, "-c", script], input=answers.encode("utf-8"),
                                capture_output=True, env=env, timeout=15)
        output = (result.stdout + result.stderr).decode("utf-8")
        self.assertEqual(result.returncode, expected, output)
        return output

    def select(self, platform, pages, answers, expected=0, latest=None):
        latest = latest if latest is not None else self.release("latest")
        (self.work / "latest.json").write_text(json.dumps(latest), encoding="utf-8")
        for number, releases in enumerate(pages, 1):
            (self.work / f"page{number}.json").write_text(json.dumps(releases), encoding="utf-8")
        return self.run_shell(platform, r'''
IMAGE_FILENAME_GZ=firmware.img.gz
fetch_release_json() {
    printf '%s\n' "$1" >> "$FIXTURES/requests"
    case "$1" in
        */latest) cat "$FIXTURES/latest.json" ;;
        *page=*) cat "$FIXTURES/page${1##*&page=}.json" ;;
        *) return 1 ;;
    esac
}
select_release
printf 'SELECTED=%s\n' "$RELEASE_TAG"
''', answers, expected)

    @staticmethod
    def release(tag, available=True, **extra):
        return dict(tag_name=tag, draft=False, prerelease=False,
                    assets=[dict(name="firmware.img.gz" if available else "other.img.gz")], **extra)

    def test_latest_default_skips_history_request(self):
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                output = self.select(platform, [], "\n")
                self.assertIn("SELECTED=latest", output)
        self.assertNotIn("per_page", (self.work / "requests").read_text())

    def test_historical_release_and_pagination(self):
        first = [self.release(f"2026.10.{day:02d}-immortalwrt") for day in range(17, 7, -1)]
        second = [self.release("2026.10.01-immortalwrt"), self.release("2026.09.27-immortalwrt")]
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                output = self.select(platform, [first, second], "h\nn\np\nn\n2\n")
                self.assertIn("SELECTED=2026.09.27-immortalwrt", output)

    def test_missing_asset_and_invalid_number_reprompt(self):
        pages = [[self.release("missing", False), self.release("usable")]]
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                output = self.select(platform, pages, "h\nabc\n01\n99\n1\n2\n")
                self.assertIn("不可选", output)
                self.assertIn("SELECTED=usable", output)

    def test_history_can_return_to_latest_or_cancel(self):
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                output = self.select(platform, [[]], "h\nn\np\n0\n")
                self.assertIn("最后一页", output)
                self.assertIn("第一页", output)
                self.assertIn("SELECTED=latest", output)
                output = self.select(platform, [[]], "h\nq\n")
                self.assertIn("操作已取消", output)
                self.assertNotIn("SELECTED=", output)

    def test_drafts_and_prereleases_are_not_selectable(self):
        draft = self.release("draft")
        draft["draft"] = True
        preview = self.release("preview")
        preview["prerelease"] = True
        for platform in PLATFORMS:
            output = self.select(platform, [[draft, preview, self.release("stable")]], "h\n1\n")
            self.assertIn("SELECTED=stable", output)
            self.assertNotIn("1) draft", output)

    def test_eof_and_api_errors_do_not_accept_defaults(self):
        for platform in PLATFORMS:
            self.select(platform, [], "", expected=1)
            output = self.select(platform, [], "", expected=1,
                                 latest={"message": "API rate limit exceeded"})
            self.assertIn("API rate limit exceeded", output)

    def test_checksum_matches_exact_filename_and_rejects_duplicates(self):
        digest = "a" * 64
        for platform in PLATFORMS:
            (self.work / "sums").write_text(
                f"{'b' * 64}  docker-firmware.img.gz\r\n{digest.upper()} *./firmware.img.gz\r\n",
                encoding="utf-8", newline="")
            output = self.run_shell(platform, r'''
IMAGE_FILENAME_GZ=firmware.img.gz
CHECKSUM_PATH="$FIXTURES/sums"
get_expected_checksum
''')
            self.assertEqual(output.strip(), digest)
            with (self.work / "sums").open("a") as stream:
                stream.write(f"{digest}  firmware.img.gz\n")
            self.run_shell(platform, 'IMAGE_FILENAME_GZ=firmware.img.gz; CHECKSUM_PATH="$FIXTURES/sums"; get_expected_checksum', expected=1)

    def test_partial_download_failure_and_wget_fallback(self):
        for platform in PLATFORMS:
            code = r'''
curl() {
    while (($#)); do
        if [[ "$1" == -o ]]; then printf partial > "$2"; return 1; fi
        shift
    done
    return 1
}
wget() { return 1; }
if download_file https://example.invalid/file "$FIXTURES/image"; then exit 99; fi
[[ ! -e "$FIXTURES/image" && ! -e "$FIXTURES/image.part" ]]
wget() {
    while (($#)); do
        if [[ "$1" == -O ]]; then printf complete > "$2"; return 0; fi
        shift
    done
    return 1
}
download_file https://example.invalid/file "$FIXTURES/image"
[[ $(cat "$FIXTURES/image") == complete && ! -e "$FIXTURES/image.part" ]]
rm "$FIXTURES/image"
'''
            self.run_shell(platform, code)

    def test_cleanup_preserves_unrelated_files_and_completed_image(self):
        for platform in PLATFORMS:
            self.run_shell(platform, r'''
mkdir -p "$FIXTURES/work"
cd "$FIXTURES"
printf untouched > .part
TMP_DIR="$FIXTURES/work"
IMAGE_PATH_GZ=""
CHECKSUM_PATH=""
printf image > "$TMP_DIR/firmware.img"
printf metadata > "$TMP_DIR/release-api.json"
cleanup
[[ -e .part && -e "$TMP_DIR/firmware.img" && ! -e "$TMP_DIR/release-api.json" ]]
''')

    def test_dispatcher_preserves_local_arguments_and_exit_status(self):
        dispatcher = self.work / "update_openwrt.sh"
        shutil.copyfile(ROOT / dispatcher.name, dispatcher)
        for platform in PLATFORMS:
            stub = self.work / f"update_openwrt_{platform}.sh"
            stub.write_text('#!/bin/bash\nprintf "ARG=<%s>\\n" "$@"\nexit 17\n', newline="\n")
        result = subprocess.run([BASH, dispatcher.as_posix(), "one two", "--flag"],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertEqual(result.stdout, "ARG=<one two>\nARG=<--flag>\n")

    def test_online_dispatcher_forwards_arguments_and_cleans_download(self):
        (self.work / "remote.sh").write_text(
            '#!/bin/bash\nprintf "SCRIPT=%s\\n" "$0"\nprintf "ARG=<%s>\\n" "$@"\nexit 17\n',
            newline="\n")
        code = r'''
curl() {
    while (($#)); do
        if [[ "$1" == -o ]]; then cp "$FIXTURES/remote.sh" "$2"; return; fi
        shift
    done
    return 1
}
wget() { return 1; }
export -f curl wget
status=0
bash <(cat "$DISPATCHER") 'one two' --flag > "$FIXTURES/output" || status=$?
[[ "$status" == 17 ]]
cat "$FIXTURES/output"
downloaded=$(sed -n 's/^SCRIPT=//p' "$FIXTURES/output")
[[ -n "$downloaded" && ! -e "$downloaded" && ! -d "$(dirname "$downloaded")" ]]
'''
        self.env["DISPATCHER"] = (ROOT / "update_openwrt.sh").as_posix()
        output = self.run_shell("x86", code)
        self.assertIn("ARG=<one two>\nARG=<--flag>", output)
        self.assertNotIn("ARG=<update_openwrt_x86.sh>", output)

    def test_invalid_json_response_is_rejected(self):
        for platform in PLATFORMS:
            output = self.run_shell(platform, r'''
TMP_DIR="$FIXTURES"
download_file() { printf '<html>error</html>' > "$2"; }
fetch_release_json https://example.invalid/releases
''', expected=1)
            self.assertIn("无效数据", output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
