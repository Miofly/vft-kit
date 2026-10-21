// wxapkg-cli: command-line wrapper around github.com/wux1an/wxapkg/wechat.
//
// Upstream v2 ships only a Wails GUI. This file is copied into the upstream
// clone as cmd/wxapkg-cli and built by ../wxapkg.sh, so it reuses the
// upstream scan / decrypt / unpack / beautify logic unchanged.
//
//	wxapkg-cli paths
//	wxapkg-cli scan   [-root DIR] [-grep TEXT] [-n 20] [-json]
//	wxapkg-cli unpack [-o DIR] [-wxid WXID] [-no-beautify] TARGET
//
// TARGET is a wxid (latest cached version is used), a version directory,
// or a single .wxapkg file.
package main

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha1"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/wux1an/wxapkg/wechat"
	"golang.org/x/crypto/pbkdf2"
)

var reWxID = regexp.MustCompile(`^wx[0-9a-f]{16}$`)

type appEntry struct {
	WxID       string   `json:"wxid"`
	Root       string   `json:"root"`
	VersionDir string   `json:"versionDir"`
	Modified   string   `json:"modified"`
	Size       int64    `json:"size"`
	Packages   []string `json:"packages"`
	Encrypted  bool     `json:"encrypted"`
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "paths":
		res := wechat.Platform.GetDefaultPaths()
		fmt.Print(res.Logs)
	case "scan":
		err = cmdScan(os.Args[2:])
	case "unpack":
		err = cmdUnpack(os.Args[2:])
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `usage:
  wxapkg-cli paths
  wxapkg-cli scan   [-root DIR] [-grep TEXT] [-n 20] [-json]
  wxapkg-cli unpack [-o DIR] [-wxid WXID] [-no-beautify] <wxid|version-dir|file.wxapkg>`)
}

func roots(custom string) []string {
	if custom != "" {
		return []string{custom}
	}
	return wechat.Platform.GetDefaultPaths().Paths
}

// latestVersionDir picks the newest sub directory (WeChat keeps one per version).
func latestVersionDir(appDir string) (string, time.Time) {
	entries, _ := os.ReadDir(appDir)
	var best string
	var bestTime time.Time
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		if best == "" || info.ModTime().After(bestTime) {
			best, bestTime = filepath.Join(appDir, e.Name()), info.ModTime()
		}
	}
	if best == "" {
		info, _ := os.Stat(appDir)
		if info != nil {
			bestTime = info.ModTime()
		}
		return appDir, bestTime
	}
	return best, bestTime
}

func isPlain(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	head := make([]byte, 14)
	if n, _ := f.Read(head); n < 14 {
		return false
	}
	return head[0] == 0xBE && head[13] == 0xED
}

func collectApps(root string) []appEntry {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var apps []appEntry
	for _, e := range entries {
		if !e.IsDir() || !reWxID.MatchString(e.Name()) {
			continue
		}
		appDir := filepath.Join(root, e.Name())
		vdir, mtime := latestVersionDir(appDir)
		files, _ := wechat.ListFilesWithExtension(vdir, ".wxapkg")
		entry := appEntry{WxID: e.Name(), Root: root, VersionDir: vdir, Modified: mtime.Format("2006-01-02 15:04")}
		for _, f := range files {
			if info, err := os.Stat(f); err == nil {
				entry.Size += info.Size()
			}
			rel, _ := filepath.Rel(vdir, f)
			entry.Packages = append(entry.Packages, rel)
			if !isPlain(f) {
				entry.Encrypted = true
			}
		}
		apps = append(apps, entry)
	}
	return apps
}

// decrypt mirrors the unexported upstream decryptWxapkgFile (V1MMWX format).
func decrypt(wxid string, data []byte) []byte {
	if len(data) < 1024+6 {
		return data
	}
	dk := pbkdf2.Key([]byte(wxid), []byte("saltiest"), 1000, 32, sha1.New)
	block, _ := aes.NewCipher(dk)
	head := make([]byte, 1024)
	cipher.NewCBCDecrypter(block, []byte("the iv: 16 bytes")).CryptBlocks(head, data[6:1024+6])
	xorKey := byte(0x66)
	if len(wxid) >= 2 {
		xorKey = wxid[len(wxid)-2]
	}
	tail := make([]byte, len(data)-1024-6)
	for i, b := range data[1024+6:] {
		tail[i] = b ^ xorKey
	}
	return append(head[:1023], tail...)
}

func containsText(wxid string, files []string, needle []byte) bool {
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		if !(len(data) > 13 && data[0] == 0xBE && data[13] == 0xED) {
			data = decrypt(wxid, data)
		}
		if bytes.Contains(data, needle) {
			return true
		}
	}
	return false
}

func cmdScan(args []string) error {
	fs := flag.NewFlagSet("scan", flag.ExitOnError)
	root := fs.String("root", "", "packages root (default: auto-detect WeChat dirs)")
	grep := fs.String("grep", "", "only list apps whose (decrypted) packages contain this text")
	limit := fs.Int("n", 20, "max apps to print, newest first (0 = all)")
	asJSON := fs.Bool("json", false, "print JSON")
	_ = fs.Parse(args)

	var apps []appEntry
	for _, r := range roots(*root) {
		apps = append(apps, collectApps(r)...)
	}
	if *grep != "" {
		var hit []appEntry
		for _, a := range apps {
			var full []string
			for _, p := range a.Packages {
				full = append(full, filepath.Join(a.VersionDir, p))
			}
			if containsText(a.WxID, full, []byte(*grep)) {
				hit = append(hit, a)
			}
		}
		apps = hit
	}
	sort.Slice(apps, func(i, j int) bool { return apps[i].Modified > apps[j].Modified })
	if *limit > 0 && len(apps) > *limit {
		apps = apps[:*limit]
	}

	if *asJSON {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(apps)
	}
	if len(apps) == 0 {
		fmt.Println("no mini program package found")
		return nil
	}
	for _, a := range apps {
		flagEnc := ""
		if a.Encrypted {
			flagEnc = " encrypted"
		}
		fmt.Printf("%s  %s  %6.1fMB  %d pkg%s  %s\n", a.WxID, a.Modified, float64(a.Size)/1024/1024, len(a.Packages), flagEnc, a.VersionDir)
	}
	return nil
}

func findApp(wxid string) (string, error) {
	for _, r := range roots("") {
		dir := filepath.Join(r, wxid)
		if info, err := os.Stat(dir); err == nil && info.IsDir() {
			vdir, _ := latestVersionDir(dir)
			return vdir, nil
		}
	}
	return "", fmt.Errorf("wxid %s not found under WeChat package roots; open the mini program in WeChat first", wxid)
}

// guessWxID walks up the path to find a wx[0-9a-f]{16} segment (decrypt key).
func guessWxID(path string) string {
	for p := path; p != "/" && p != "."; p = filepath.Dir(p) {
		if reWxID.MatchString(filepath.Base(p)) {
			return filepath.Base(p)
		}
	}
	return ""
}

func cmdUnpack(args []string) error {
	fs := flag.NewFlagSet("unpack", flag.ExitOnError)
	out := fs.String("o", ".", "output directory; files go to <o>/<wxid>")
	wxid := fs.String("wxid", "", "decrypt key (only needed for encrypted Windows packages when path has no wxid)")
	noBeautify := fs.Bool("no-beautify", false, "skip JS/HTML/JSON beautify")
	// Allow flags after the positional target.
	var positional []string
	for len(args) > 0 {
		_ = fs.Parse(args)
		args = fs.Args()
		if len(args) > 0 {
			positional = append(positional, args[0])
			args = args[1:]
		}
	}
	if len(positional) != 1 {
		return fmt.Errorf("need exactly one target (wxid, version dir, or .wxapkg file)")
	}
	target := positional[0]

	location := target
	if reWxID.MatchString(target) {
		dir, err := findApp(target)
		if err != nil {
			return err
		}
		location = dir
		if *wxid == "" {
			*wxid = target
		}
	}
	location, _ = filepath.Abs(location)
	info, err := os.Stat(location)
	if err != nil {
		return err
	}
	if *wxid == "" {
		*wxid = guessWxID(location)
	}

	name := *wxid
	if name == "" {
		name = strings.TrimSuffix(filepath.Base(location), filepath.Ext(location))
	}
	outDir, _ := filepath.Abs(*out)
	savePath := filepath.Join(outDir, name)

	item := &wechat.WxapkgItem{
		WxId:       name,
		Location:   location,
		EncryptKey: *wxid,
		IsDir:      info.IsDir(),
	}
	opts := &wechat.UnpackOptions{
		EnableDecrypt:      true,
		EnableJsBeautify:   !*noBeautify,
		EnableHtmlBeautify: !*noBeautify,
		EnableJsonBeautify: !*noBeautify,
		OutputDir:          outDir,
		SavePath:           savePath,
	}

	var last wechat.WxapkgItem
	wechat.NewUnpacker(item, opts).UnpackWithStatusCallback(func(it *wechat.WxapkgItem) {
		last = *it
	})
	if last.UnpackStatus == wechat.StatusTypeError {
		return fmt.Errorf("%s", last.UnpackErrorMessage)
	}
	fmt.Printf("unpacked %d files from %d package(s)\n  source: %s\n  output: %s\n", last.UnpackCurrent, len(item.WxapkgFilePaths), location, savePath)
	return nil
}
