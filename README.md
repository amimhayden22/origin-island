# Origin Island

**Notifikasi ala Dynamic Island untuk [Claude Code](https://claude.com/claude-code) di Windows, dengan atau tanpa WSL.**

Pil kecil di tepi atas layar yang memberi tahu saat Claude selesai, butuh izin, atau gagal, lengkap
dengan maskot pixel **ogin** dan sisa kuota Claude Anda, tanpa perlu membuka `/usage`.

Dibuat oleh **[Gus Khamim](https://guskhamim.com)** · [Situs resmi](https://amimhayden22.github.io/origin-island/)

![Claude selesai](docs/done.png)

## Fitur

- **Notifikasi + suara** saat Claude selesai, butuh izin/perhatian, atau gagal. Klik notifikasinya
  untuk langsung ke terminal tempat sesi itu berjalan (Windows Terminal atau VS Code).
- **Maskot ogin** (roket pixel 16×16) dengan animasi per status: `idle`, `thinking`, `working`,
  `waiting`, `done`, `error`.
- **Kuota langganan** sesi 5 jam & mingguan sebagai cincin, lengkap dengan hitung mundur reset.
  Datanya diambil dari statusline Claude Code (fitur resmi), jadi tidak ada request tambahan dan
  token login Anda tidak disentuh.
- **Banyak sesi sekaligus**: daftar sesi aktif dan statusnya; klik untuk membuka terminalnya.
- **Multi-monitor**: seret pil ke kiri/kanan atau ke monitor lain; posisi diingat.
- **Ringan & sopan**: hanya berjalan selama WSL hidup, sembunyi saat ada video/game fullscreen,
  tidak mencuri fokus, tidak muncul di taskbar/Alt-Tab.

## Tampilan

| Kondisi | Tampilan |
|---|---|
| **Siaga** — maskot + cincin kuota (luar: 5 jam, dalam: mingguan) | ![Siaga](docs/idle.png) |
| **Bekerja** — maskot bekerja, nama proyek tampil | ![Bekerja](docs/working.png) |
| **Hover** — detail kuota, sesi aktif, volume, tombol | ![Hover](docs/hover.png) |
| **Butuh izin** — notifikasi + suara | ![Butuh izin](docs/attention.png) |
| **Selesai** — cuplikan balasan terakhir Claude + suara | ![Selesai](docs/done.png) |

## Persyaratan

| | |
|---|---|
| **Windows 10/11** | PowerShell & WPF sudah bawaan Windows, tidak perlu memasang apa pun |
| **Claude Code**, sudah login | Di Windows atau di dalam WSL. Notifikasi bekerja lewat hook Claude Code |
| **`python3` dan `git`** | Hanya untuk versi WSL, sudah ada di Ubuntu bawaan |
| **Langganan Claude (Pro/Max)** | Untuk menampilkan **kuota**. Dengan API key, notifikasi tetap jalan tetapi kuota tidak tampil |
| **Claude Code versi terbaru** | Versi lama belum mengirim data kuota ke statusline, jadi kuota tidak tampil |

## Pasang

### Cara termudah: minta Claude Code yang memasang

Sudah punya Claude Code? Tidak perlu memilih apa pun, cukup salin pesan ini ke Claude Code:

> Tolong pasang Origin Island dari https://github.com/amimhayden22/origin-island. Ikuti bagian
> "Untuk Claude Code" di README-nya.

Setujui kalau Claude meminta izin. Setelah selesai, **keluar dari Claude Code lalu jalankan `claude` lagi**,
kemudian kirim satu prompt. Pil muncul di tengah atas layar, dan kuota tampil setelah prompt pertama.

### Untuk Claude Code

Bagian ini petunjuk untuk Claude Code yang diminta memasang Origin Island:

1. Tentukan tempat Anda berjalan. WSL bila `uname -r` berisi `microsoft`, Windows bila berjalan langsung
   di Windows.
2. **Di WSL:** jalankan `git clone https://github.com/amimhayden22/origin-island.git`, lalu
   `cd origin-island && ./install.sh`.
3. **Di Windows:** jalankan di PowerShell:
   `powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/amimhayden22/origin-island/main/install.ps1 | iex"`.
   Menu pilihan otomatis dilewati saat dijalankan oleh Claude Code.
4. Sebutkan ke pengguna bahwa installer mengubah `settings.json` Claude Code (dan `~/.bashrc` di WSL).
5. Akhiri dengan meminta pengguna **membuka ulang sesi Claude Code**, karena sesi yang sedang berjalan tidak
   memuat statusline baru sehingga kuotanya tidak diperbarui.

Kalau Claude Code tidak bisa menjalankannya, pasang sendiri dengan cara di bawah.

### Pasang sendiri

Buka PowerShell, lalu jalankan:

```powershell
irm https://raw.githubusercontent.com/amimhayden22/origin-island/main/install.ps1 | iex
```

Installer akan bertanya:

```text
Pasang Origin Island untuk:
  [1] Windows (direkomendasikan)
  [2] Windows + WSL (biasanya untuk programmer)
```

**Tidak yakin? Tekan Enter saja.** Kalau Claude Code hanya ada di WSL, installer menyarankan pilihan 2. Pengguna
WSL juga bisa memasang dari terminal WSL dengan `git clone`, lalu `./install.sh`.

Setelah itu **buka ulang sesi Claude Code yang sedang berjalan** (hook langsung aktif, tetapi statusline
baru dimuat di sesi baru), lalu kirim satu prompt.

> **Perhatikan:** kuota hanya tampil bila login dengan langganan **Pro/Max** dan Anda **belum** punya
> statusline sendiri (statusline yang sudah ada tidak ditimpa). Di versi WSL, pengguna **zsh** tidak mendapat
> autostart saat terminal dibuka, tetapi pil tetap menyala begitu Claude Code dipakai.

Dengan pilihan 2, sesi Windows dan WSL tampil dalam **satu pil yang sama**.

### Apa saja yang diubah installer

| Lokasi | Perubahan |
|---|---|
| `%LOCALAPPDATA%\OriginIsland\` | Aplikasi Windows, ikon, suara, `config.json`, log |
| `~/.claude/island/` (WSL) atau `%LOCALAPPDATA%\OriginIsland\hooks\` (Windows) | Skrip hook, statusline, dan uninstall |
| `~/.claude/settings.json` | Menambah **hook** dan **`statusLine`** (cadangan: `settings.json.bak-island`). Statusline milik Anda yang sudah ada **tidak** ditimpa |
| `~/.bashrc` (hanya WSL) | Satu blok `# >>> origin-island >>>` untuk menyalakan island saat terminal dibuka |

Hapus semuanya kapan saja lewat tombol **Uninstall** (ikon tempat sampah) di panel island, atau
`./uninstall.sh` dari terminal WSL, atau `uninstall.ps1` di folder aplikasi untuk versi Windows. Semuanya
ikut melepas versi lain bila keduanya terpasang.

### Kapan island berjalan

Island tidak ikut menyala saat Windows login. Versi Windows menyala saat Claude Code dipakai dan tetap
berjalan sampai ditutup atau Windows keluar. Versi WSL **hanya berjalan selama WSL hidup** (supaya startup
tidak berat karena ikut membangunkan WSL):
- menyala saat terminal WSL dibuka atau saat Claude Code dipakai (hook `SessionStart` /
  `UserPromptSubmit`), termasuk setelah ditutup dengan tombol X;
- keluar sendiri ±30 detik setelah WSL berhenti.

## Pemakaian

- **Arahkan kursor** ke pil untuk melihat detail kuota dan sesi aktif.
- **Klik** pil/notifikasi untuk membuka terminal sesi terkait. Baris sesi di panel juga bisa diklik.
- **Seret ke kiri/kanan** untuk memindahkan pil, termasuk ke monitor lain.
- **Geser slider Volume** di panel hover untuk mengatur besar suara notifikasi. Suara contoh diputar
  saat slider dilepas, dan pilihan Anda diingat.
- Tombol di panel hover:

  | Ikon | Fungsi |
  |---|---|
  | `refresh.svg` | Baca ulang kuota terakhir dan tampilkan waktu datanya. Angkanya berubah setelah Claude Code menerima respons |
  | `sound-on.svg` / `sound-off.svg` | Nyalakan/matikan suara |
  | `bell.svg` | Tes suara notifikasi |
  | `center.svg` | Ke tengah layar tempat island berada |
  | `trash.svg` | Uninstall Origin Island (dengan konfirmasi) |
  | `exit.svg` (kanan atas) | Tutup island |

### Status maskot

| Status | Kapan |
|---|---|
| `idle` | Tidak ada sesi aktif |
| `thinking` | Claude berpikir (setelah prompt, di antara langkah) |
| `working` | Alat (tool) sedang berjalan |
| `waiting` | Butuh izin atau perhatian |
| `done` | Selesai |
| `error` | Alat gagal (sekilas), atau Claude gagal (notifikasi merah) |

Frame dan palet maskot ada di `icons/ogin-pixel.json`.

### Kustomisasi

- **Suara**: ganti file di `sounds/` (MP3 atau WAV) lalu jalankan `./install.sh` lagi.
- **Ikon**: ganti SVG di `icons/` (isi maupun garis).
- **Pengaturan** di `%LOCALAPPDATA%\OriginIsland\config.json`:

  | Kunci | Default | Arti |
  |---|---|---|
  | `notifySeconds` | `8` | Lama notifikasi tampil |
  | `sound` | `true` | Suara notifikasi |
  | `soundVolume` | `1.0` | Volume (0–1) |
  | `soundDone`, `soundAttention`, `soundError` | file di `sounds/` | Path Windows ke suara sendiri |
  | `hideOnFullscreen` | `true` | Sembunyi saat video/game fullscreen |
  | `exitWhenWslStops` | `true` | Keluar saat WSL berhenti |
  | `usageApiFallback` | `false` | API kuota cadangan (lihat di bawah) |
  | `pollSeconds` | `300` | Jeda minimum API kuota cadangan (min. 300) |

## Cara kerja

```
Claude Code (WSL) --hook-------> island_hook.py ------> %LOCALAPPDATA%\OriginIsland\events.jsonl
Claude Code (WSL) --statusline-> island_statusline.py -> %LOCALAPPDATA%\OriginIsland\usage.json
                                                                   |
island.ps1 (Windows, PowerShell + WPF) <--- dibaca tiap 0,5 detik --+
```

- Secara default Origin Island **hanya memakai fitur resmi Claude Code** (hook & statusline), tidak
  membaca token login, dan tidak menghubungi server mana pun.
- **Kuota** diambil dari data `rate_limits` yang sudah diterima Claude Code dan diteruskan ke
  statusline, jadi angkanya diperbarui setiap Anda memakai Claude Code. Saat Claude Code lama tidak
  dipakai, angka terakhir tetap tampil beserta jam pembaruannya.

### API kuota cadangan (opsional, mati secara default)

Dengan `"usageApiFallback": true` di `config.json`, island juga memanggil
`api.anthropic.com/api/oauth/usage` (endpoint yang sama dengan `/usage`) saat data statusline lebih
tua dari 10 menit, paling cepat tiap 5 menit; bila kena 429, island menunggu makin lama (5 → 30 menit).
Untuk itu island **membaca token OAuth** dari `~/.claude/.credentials.json` (tidak disimpan ke tempat
lain dan tidak di-refresh). Endpoint ini **tidak terdokumentasi resmi**, jadi aktifkan dengan risiko
sendiri.

## Batasan

- Klik notifikasi memilih **tab** sesi di Windows Terminal dengan mengganti judul tab sesaat. Profil WSL
  bawaan mengunci judul tab, jadi kalau ada dua tab atau lebih yang dikunci dengan nama distro yang sama,
  island hanya memunculkan jendelanya. Untuk membuka kuncinya, tambahkan
  `"suppressApplicationTitle": false` pada profil distro di setelan Windows Terminal.
- Di VS Code, klik memunculkan jendela folder sesi, tetapi belum bisa memilih panel terminalnya.
- Di Windows tanpa WSL, klik memunculkan jendela terminal, tetapi belum bisa memilih tab yang tepat.
- Pembatalan perintah (Esc) terdeteksi dari file status sesi dan transcript Claude Code karena tidak ada
  hook untuk itu; keduanya bukan API resmi, jadi deteksinya bisa berhenti bekerja setelah Claude Code
  diperbarui.
- Autostart saat terminal dibuka hanya untuk **bash**. Pengguna zsh/fish tetap mendapat island saat
  Claude Code dipakai (lewat hook).
- Kuota hanya diperbarui saat Claude Code dipakai (kecuali API cadangan dinyalakan).
- Hook hanya terpasang di distro WSL tempat `install.sh` dijalankan.

## Pemecahan masalah

- **Pil tidak muncul**: buka terminal WSL baru atau kirim prompt ke Claude Code. Cek
  `%LOCALAPPDATA%\OriginIsland\island.log`.
- **Melapor masalah**: sertakan isi `island.log` di atas dan output `./install.sh`.
- **Antivirus** kadang memblokir skrip `.vbs`/PowerShell tersembunyi. Izinkan
  `%LOCALAPPDATA%\OriginIsland\start-island.vbs`.
- **Kuota berbeda dengan `/usage`**: lihat jam di kiri bawah panel. Kalau sudah lama, atau muncul peringatan
  "Kuota beku", buka ulang sesi Claude Code. Angka island berasal dari respons terakhir Claude Code, jadi
  pemakaian di perangkat lain baru terlihat setelah request berikutnya.
- **Kuota tidak tampil**: pastikan login dengan langganan Claude (bukan API key) dan kirim satu prompt
  supaya statusline mengirim data.

## Lisensi & kredit

- Dibuat oleh **[Gus Khamim](https://guskhamim.com)**. Masukan dan laporan
  masalah: buka [issue](https://github.com/amimhayden22/origin-island/issues).
- Kode: [MIT](LICENSE).
- Maskot **ogin** dan ikon: karya Gus Khamim untuk proyek ini.
- Suara notifikasi: dari [Pixabay](https://pixabay.com/id/). Suara notifikasi gagal: *error notification* oleh Universfield.

Origin Island adalah proyek independen dan **tidak berafiliasi** dengan Anthropic atau Apple.
*Claude* dan *Claude Code* adalah merek dagang Anthropic; *Dynamic Island* adalah merek dagang Apple.
