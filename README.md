# Smart Load-Diverter Comparator (SLDC) IP Core

IP Core komparator beban cerdas (*Smart Load-Diverter Comparator - SLDC*) berbasis arsitektur **Hardware-Software Co-Design**. Dirancang untuk otomasi energi pintar, proteksi kelebihan beban (*over-current protection*), maupun pengalihan daya berlebih (seperti *solar surplus power diversion*) pada sistem SoC FPGA modern (misalnya **AMD / Xilinx Kria KV260**, **Zynq UltraScale+ MPSoC**, **Zynq-7000**, maupun **ARM Cortex-M/A**).

---

## 🖼 Vivado Block Design (Kria KV260 & Zynq UltraScale+ MPSoC)

<img width="1090" height="342" alt="Screenshot 2026-11-01 161136" src="https://github.com/user-attachments/assets/3aaf7c20-ae2c-43c1-8f85-85526eb4d576" />


> **Keterangan Blok & Interkoneksi Hardware pada Diagram di atas:**
> 1. **`zynq_ultra_ps_e_0` (Zynq UltraScale+ MPSoC)**: Processing System (PS) board Kria KV260 yang menjalankan Linux/Edge-AI. Mengontrol IP melalui port Master AXI Full-Power Domain (`M_AXI_HPM0_FPD`), menyediakan fabric clock 100 MHz (`pl_clk0`), serta sinyal reset awal (`pl_resetn0`).
> 2. **`axi_smc` (AXI SmartConnect)**: Interconnect bus AXI4 berkecepatan tinggi yang merutekan transaksi dari master PS (`S00_AXI`) ke port slave IP Core (`M00_AXI`).
> 3. **`rst_ps8_0_99M` (Processor System Reset)**: Mengatur reset sinkronisasi clock (`peripheral_aresetn[0:0]`) untuk AXI SmartConnect dan SLDC IP Core.
> 4. **`smart_diverter_axi_0` (`smart_diverter_axi_v1_0`)**: IP Core kustom SLDC yang menerima injeksi nilai ambang batas (*threshold*) dari AI, membandingkannya dengan input sensor arus riil `sensor_current_in[31:0]`, dan menggerakkan output `relay_out_0` menuju Solid-State Relay (SSR).

---

## 📌 Daftar Isi
1. [Gambaran Umum](#-gambaran-umum)
2. [Fitur Utama](#-fitur-utama)
3. [Arsitektur Co-Design (Hardware vs Software)](#-arsitektur-co-design-hardware-vs-software)
4. [Struktur File Repository](#-struktur-file-repository)
5. [Peta Register (Memory-Mapped Register Map)](#-peta-register-memory-mapped-register-map)
6. [Deskripsi Port & Sinyal Antarmuka](#-deskripsi-port--sinyal-antarmuka)
   - [Sinyal Eksternal / Real-World](#1-sinyal-eksternal--real-world)
   - [Sinyal Antarmuka APB (smart_diverter_apb.v)](#2-sinyal-antarmuka-apb-smart_diverter_apbv)
   - [Sinyal Antarmuka AXI4-Lite (smart_diverter_axi.v)](#3-sinyal-antarmuka-axi4-lite-smart_diverter_axiv)
7. [Logika Operasi Komparator & Keamanan](#-logika-operasi-komparator--keamanan)
8. [Panduan Integrasi Vivado & FPGA](#-panduan-integrasi-vivado--fpga)
   - [Langkah Packaging & Block Design](#langkah-merakit-block-design-vivado)
   - [Physical Constraints (.xdc) untuk Kria KV260](#physical-constraints-xdc-untuk-kria-kv260)
   - [Integrasi pada Sistem APB](#integrasi-pada-sistem-apb)
9. [Panduan Simulasi & Verifikasi Testbench](#-panduan-simulasi--verifikasi-testbench)
10. [Contoh Software Driver (C & Python)](#-contoh-software-driver-c--python)
    - [Driver Bahasa C (Bare-Metal / FreeRTOS)](#1-driver-bahasa-c-bare-metal--freertos)
    - [Driver Python (Linux / PYNQ / Ubuntu Kria)](#2-driver-python-linux--pynq--ubuntu-kria)
11. [Spesifikasi Teknis](#-spesifikasi-teknis)

---

## 📖 Gambaran Umum

Dalam sistem kelistrikan pintar, beban listrik sering kali berfluktuasi secara dinamis. Untuk memprediksi batas aman (*threshold*) atau mendeteksi surplus daya surya, algoritma **Edge-AI** (Machine Learning/Deep Learning) sangat efektif dalam menganalisis data historis dan tren lingkungan.

Namun, eksekusi pemutusan sirkuit atau pengalihan daya ke Solid-State Relay (SSR) menuntut **latensi nol (zero-latency) dan respon deterministik instan** yang mustahil dijamin oleh sistem operasi CPU yang rentan terhadap *scheduling latency*, *context switching*, dan *interrupt jitter*.

**SLDC IP Core** mengimplementasikan sinergi optimal:
* **Sisi Software / Edge-AI (CPU/NPU)**: Menghitung secara berkala ambang batas optimal dan menginjeksinya ke register IP melalui bus sistem standar (AXI atau APB).
* **Sisi Hardware (FPGA Fabric)**: Mengamati arus beban secara kontinu dan mengeksekusi komparasi daya langsung pada gerbang logika tanpa siklus penundaan CPU, serta memicu relai secara instan saat kondisi terpenuhi.

---

## ⚡ Fitur Utama

- **Dukungan Dua Standar Bus Populer**:
  - `smart_diverter_axi.v`: Menggunakan antarmuka **AXI4-Lite Slave 32-bit**, langsung kompatibel dengan Vivado IP Integrator, Zynq UltraScale+ (Kria KV260), Zynq-7000, dan MicroBlaze.
  - `smart_diverter_apb.v`: Menggunakan antarmuka **AMBA APB3/APB4 Slave**, berdaya sangat rendah, hemat area gerbang logic (*zero wait-state* `PREADY = 1`).
- **Respon Komparasi Instan (*Zero-Latency*)**: Menggunakan komparator sekuensial/kombinasional berkecepatan tinggi yang merespons lonjakan arus pada frekuensi clock fabric (100 MHz+).
- **Safety Interlock & Fail-Safe**:
  - Relai dipaksa mati (`relay_out = 0`) selama masa reset sistem.
  - Saat sistem dinonaktifkan melalui register kontrol (`CTRL_REG[0] = 0`), relai langsung dimatikan paksa tanpa memedulikan nilai sensor (*Emergency Shutoff*).
- **Live Telemetry Monitoring**: CPU dapat memantau kembali arus sensor riil (`SENSOR_REG`) dan status aktif relai (`STAT_REG`) kapan saja melalui pembacaan bus memori.
- **Dukungan Akses Byte (*Write Strobes*)**: Mendukung `WSTRB` pada varian AXI4-Lite untuk manipulasi byte granular.
- **Read-Only Protection**: Register status dan sensor aman dari kerusakan akibat penulisan data yang tidak disengaja oleh software.

---

## 🏗 Arsitektur Co-Design (Hardware vs Software)

```
                 +-----------------------------------------------+
                 |       Edge-AI Model / Processing System       |
                 |      (Kria KV260 ARM Cortex-A53 / Linux)      |
                 +-----------------------------------------------+
                                         |
                       AXI4-Lite / APB Memory-Mapped Bus
                                         |
+========================================v========================================+
|  SLDC IP Core Fabric (smart_diverter_axi / smart_diverter_apb)                  |
|                                                                                 |
|   +-------------------------------------------------------------------------+   |
|   | Register File (32-bit Registers)                                        |   |
|   |  - Offset 0x00: CTRL_REG      [EN, MODE]                                |   |
|   |  - Offset 0x04: STAT_REG      [Relay Status bit 0]                      |   |
|   |  - Offset 0x08: THRESHOLD_REG [AI Injected Threshold]                   |   |
|   |  - Offset 0x0C: SENSOR_REG    [Live Sensor Current Readback]            |   |
|   +-------------------------------------------------------------------------+   |
|                                  |                           ^                  |
|                           threshold_reg                      |                  |
|                                  |                           |                  |
|                                  v                           |                  |
|   [sensor_current_in] -------> [ > ] (Hardware Comparator)   |                  |
|   (32-bit dari ADC/Sensor)       |                           |                  |
|                                  v                           |                  |
|   ctrl_en (CTRL_REG[0]) -----> [ AND ] (Safety Interlock)    |                  |
|                                  |                           |                  |
|                                  v                           |                  |
|                              relay_out ----------------------+                  |
|                       (Solid-State Relay Pin Driver)                            |
+=================================================================================+
```

---

## 📁 Struktur File Repository

| Nama File | Bahasa | Deskripsi |
| :--- | :---: | :--- |
| [`smart_diverter_axi.v`](file:///c:/SLDC_ip/smart_diverter_axi.v) | Verilog HDL | Modul IP Core dengan bus interface **AXI4-Lite Slave**. Direkomendasikan untuk Xilinx Vivado & board Kria KV260. |
| [`smart_diverter_apb.v`](file:///c:/SLDC_ip/smart_diverter_apb.v) | Verilog HDL | Modul IP Core dengan bus interface **AMBA APB3/APB4 Slave**. Cocok untuk subsistem mikrokontroler ARM / low-power SoC. |
| [`tb_smart_diverter_apb.v`](file:///c:/SLDC_ip/tb_smart_diverter_apb.v) | Verilog HDL | Testbench komprehensif menguji 8 skenario pengujian fungsional dan corner-cases. |
| [`kv260_block_design.png`](file:///c:/SLDC_ip/kv260_block_design.png) | Image | Diagram Block Design Vivado resmi implementasi IP Core pada Kria KV260 Vision AI Starter Kit. |
| [`README.md`](file:///c:/SLDC_ip/README.md) | Markdown | Dokumentasi teknis terinci IP Core SLDC. |

---

## 🗺 Peta Register (Memory-Mapped Register Map)

Setiap register memiliki lebar **32-bit** (*word-aligned* dengan kelipatan alamat 4-byte):

| Offset | Nama Register | Hak Akses | Reset Value | Struktur Bit & Deskripsi Fungsional |
| :---: | :--- | :---: | :---: | :--- |
| **`0x00`** | **CTRL_REG** | R/W | `0x00000000` | **Control Register**<br>• `Bit[0]` (**EN**): Master System Enable.<br>&nbsp;&nbsp;`1` = Sistem aktif & komparator beroperasi.<br>&nbsp;&nbsp;`0` = Sistem dinonaktifkan, relai dipaksa padam (`relay_out = 0`).<br>• `Bit[1]` (**MODE**): Mode Operasi.<br>&nbsp;&nbsp;`1` = AI-Driven Dynamic Mode.<br>&nbsp;&nbsp;`0` = Manual Fixed Mode.<br>• `Bit[31:2]`: Reserved (baca sebagai `0`). |
| **`0x04`** | **STAT_REG** | RO | `0x00000000` | **Status Register** (Read-Only)<br>• `Bit[0]` (**RELAY_STATE**): Status logika riil pin `relay_out` saat ini.<br>&nbsp;&nbsp;`1` = Beban sedang dialihkan (Relay tertutup/ON).<br>&nbsp;&nbsp;`0` = Kondisi normal / relay terbuka.<br>• `Bit[31:1]`: Reserved (`0`). |
| **`0x08`** | **THRESHOLD_REG** | R/W | `0x00000000` | **AI Threshold Register**<br>• `Bit[31:0]`: Nilai ambang batas arus (integer/fixed-point) yang diinjeksi oleh algoritma Edge-AI. |
| **`0x0C`** | **SENSOR_REG** | RO | `0x00000000` | **Sensor Telemetry Register** (Read-Only)<br>• `Bit[31:0]`: Menampilkan nilai bacaan riil langsung dari pin input `sensor_current_in` untuk logging CPU. |

> [!NOTE]
> Operasi penulisan ke alamat `0x04` (`STAT_REG`) dan `0x0C` (`SENSOR_REG`) diabaikan secara aman oleh logika hardware sehingga nilai status dan telemetri sensor tidak dapat dimanipulasi oleh kesalahan penulisan program.

---

## 🔌 Deskripsi Port & Sinyal Antarmuka

### 1. Sinyal Eksternal / Real-World
| Nama Port | Arah | Lebar | Deskripsi |
| :--- | :---: | :---: | :--- |
| `sensor_current_in` | Input | 32-bit | Masukan data arus digital kontinu dari ADC (misal Xilinx XADC, modul SPI/I2C ADC, atau AXI GPIO). |
| `relay_out` | Output | 1-bit | Sinyal kendali digital langsung ke Solid-State Relay (SSR) / MOSFET switch driver. |

---

### 2. Sinyal Antarmuka APB (`smart_diverter_apb.v`)
| Port | Arah | Lebar | Standar Sinyal APB |
| :--- | :---: | :---: | :--- |
| `PCLK` | In | 1 | APB Clock |
| `PRESETn` | In | 1 | APB Asynchronous Active-Low Reset |
| `PSEL` | In | 1 | APB Peripheral Select |
| `PENABLE` | In | 1 | APB Enable (Access phase) |
| `PWRITE` | In | 1 | Transfer Direction (`1` = Write, `0` = Read) |
| `PADDR` | In | 32 | APB Address Bus |
| `PWDATA` | In | 32 | APB Write Data Bus |
| `PRDATA` | Out | 32 | APB Read Data Bus |
| `PREADY` | Out | 1 | APB Ready Response (Tersambung konstan ke `1'b1`) |

---

### 3. Sinyal Antarmuka AXI4-Lite (`smart_diverter_axi.v`)
| Kanal AXI | Port | Arah | Lebar | Deskripsi |
| :--- | :--- | :---: | :---: | :--- |
| **Global** | `S_AXI_ACLK` | In | 1 | AXI Bus Clock |
| | `S_AXI_ARESETN` | In | 1 | AXI Active-Low Reset |
| **Write Address** | `S_AXI_AWADDR` | In | 4 | Alamat tulis (Offset 0x0 - 0xC) |
| | `S_AXI_AWPROT` | In | 3 | Protection type |
| | `S_AXI_AWVALID` | In | 1 | Write address valid |
| | `S_AXI_AWREADY` | Out | 1 | Write address ready |
| **Write Data** | `S_AXI_WDATA` | In | 32 | Data tulis |
| | `S_AXI_WSTRB` | In | 4 | Write strobe (byte enable) |
| | `S_AXI_WVALID` | In | 1 | Write data valid |
| | `S_AXI_WREADY` | Out | 1 | Write data ready |
| **Write Response**| `S_AXI_BRESP` | Out | 2 | Write response (`2'b00` = OKAY) |
| | `S_AXI_BVALID` | Out | 1 | Write response valid |
| | `S_AXI_BREADY` | In | 1 | Master response ready |
| **Read Address** | `S_AXI_ARADDR` | In | 4 | Alamat baca |
| | `S_AXI_ARPROT` | In | 3 | Protection type |
| | `S_AXI_ARVALID` | In | 1 | Read address valid |
| | `S_AXI_ARREADY` | Out | 1 | Read address ready |
| **Read Data** | `S_AXI_RDATA` | Out | 32 | Data baca |
| | `S_AXI_RRESP` | Out | 2 | Read response (`2'b00` = OKAY) |
| | `S_AXI_RVALID` | Out | 1 | Read data valid |
| | `S_AXI_RREADY` | In | 1 | Master read ready |

---

## ⚙ Logika Operasi Komparator & Keamanan

Logika komparator dirancang deterministik dengan interlock keamanan:

$$\text{relay\_out} = (\text{CTRL\_REG}[0] == 1) \land (\text{sensor\_current\_in} > \text{threshold\_reg})$$

### Tabel Kebenaran Operasional:
| Status Reset (`PRESETn`/`ARESETN`) | `CTRL_REG[0]` (EN) | Kondisi Nilai Sensor | `relay_out` | Status Kerja |
| :---: | :---: | :---: | :---: | :--- |
| `0` (Sedang Reset) | X | X | **`0`** | Kondisi Aman / Reset State |
| `1` (Operasional) | `0` (Disabled) | Sembarang Arus | **`0`** | **Safety Off / Emergency Stop** |
| `1` (Operasional) | `1` (Enabled) | `sensor <= threshold` | **`0`** | Beban Aman (Normal) |
| `1` (Operasional) | `1` (Enabled) | `sensor > threshold` | **`1`** | **Diverter Aktif (Relay ON)** |

---

## 🚀 Panduan Integrasi Vivado & FPGA

### Langkah Merakit Block Design Vivado
1. **Tambahkan Repository IP**:
   - Di Vivado, buka **Project Settings $\rightarrow$ IP $\rightarrow$ Repository**, klik **`+`** dan pilih folder `C:/SLDC_ip`.
2. **Tambahkan Zynq UltraScale+ MPSoC**:
   - Tambahkan IP **Zynq UltraScale+ MPSoC**, lalu klik banner **Run Block Automation** (pilih preset Kria KV260).
3. **Tambahkan IP Smart Diverter**:
   - Tekan `Ctrl + I`, ketik `smart_diverter` dan masukkan **Smart Load-Diverter (AXI)**.
4. **Jalankan Connection Automation**:
   - Klik **Run Connection Automation** untuk menghubungkan `S_AXI` ke master `M_AXI_HPM0_FPD` dari Zynq. Vivado akan otomatis merangkai **AXI SmartConnect** (`axi_smc`) dan **Processor System Reset** (`rst_ps8_0_99M`).
5. **Koneksikan Port Hardware**:
   - Klik kanan pin `relay_out` $\rightarrow$ **Make External** (`Ctrl + T`) $\rightarrow$ beri nama `relay_out_0`.
   - Hubungkan `sensor_current_in[31:0]` ke modul ADC / AXI GPIO / logika pembaca sensor.
6. **Rapikan & Validasi**:
   - Tekan **Regenerate Layout** (`F5`) untuk menata kabel secara otomatis seperti pada diagram block design di atas.
   - Tekan `F6` untuk memvalidasi desain (*Validate Design*).

### Physical Constraints (.xdc) untuk Kria KV260
Hubungkan sinyal output relai ke pin header fisik board KV260, contohnya menggunakan **PMOD Connector (J2)** pin 1 (Package Pin `H12`):

```tcl
# ------------------------------------------------------------------------------
# Kria KV260 PMOD J2 Pin 1 Constraint untuk relay_out
# ------------------------------------------------------------------------------
set_property PACKAGE_PIN H12 [get_ports relay_out_0]
set_property IOSTANDARD LVCMOS33 [get_ports relay_out_0]
set_property SLEW SLOW [get_ports relay_out_0]
set_property DRIVE 4 [get_ports relay_out_0]
```

### Integrasi pada Sistem APB
Jika menggunakan sistem berbasis bus APB (ARM Cortex-M), instansiasi modul secara langsung:

```verilog
smart_diverter_apb u_diverter (
    .PCLK             (apb_clk),
    .PRESETn          (apb_resetn),
    .PSEL             (apb_psel),
    .PENABLE          (apb_penable),
    .PWRITE           (apb_pwrite),
    .PADDR            (apb_paddr),
    .PWDATA           (apb_pwdata),
    .PRDATA           (apb_prdata),
    .PREADY           (apb_pready),
    .sensor_current_in(w_sensor_data),
    .relay_out        (w_relay_signal)
);
```

---

## 🧪 Panduan Simulasi & Verifikasi Testbench

File [`tb_smart_diverter_apb.v`](file:///c:/SLDC_ip/tb_smart_diverter_apb.v) dirancang dengan 8 skenario pengujian komprehensif:

1. **Skenario 1 (Reset Verification)**: Memastikan setelah reset semua register bernilai `0x00000000` dan `relay_out` bernilai `0`.
2. **Skenario 2 (AI Threshold Write)**: Menulis nilai ambang batas AI (5000) ke `THRESHOLD_REG` (0x08) dan memverifikasi data via readback.
3. **Skenario 3 (System Enable)**: Mengaktifkan IP core (`CTRL_REG = 1`) dan memverifikasi relai tetap nonaktif selama sensor = 0.
4. **Skenario 4 (Dynamic Sensor Sweep)**:
   - Arus 3000 (< 5000) $\rightarrow$ `relay_out = 0`.
   - Arus dinaikkan ke 6000 (> 5000) $\rightarrow$ **`relay_out = 1` (Diverter Aktif)**.
   - Arus diturunkan kembali ke 2000 (< 5000) $\rightarrow$ `relay_out = 0`.
5. **Skenario 5 (Boundary Test)**: Nilai arus tepat sama dengan threshold (5000 == 5000); diverifikasi relai tetap mati karena syarat pemicu adalah strictly greater (`>`).
6. **Skenario 6 (Emergency Stop)**: Saat arus sangat tinggi (9000), sistem dinonaktifkan (`CTRL_REG = 0`); relai terbukti padam seketika.
7. **Skenario 7 (Read-Only Protection)**: Mencoba menimpa register `0x04` dan `0x0C`; nilai register terbukti tidak berubah (*protected*).
8. **Skenario 8 (PREADY Handshake)**: Memverifikasi bus APB merespons seketika dengan `PREADY = 1`.

### Menjalankan Simulasi dengan Icarus Verilog & GTKWave:
```bash
# Kompilasi design dan testbench
iverilog -o sim_diverter.vvp tb_smart_diverter_apb.v smart_diverter_apb.v

# Jalankan simulasi (akan mencetak status [PASS] setiap skenario)
vvp sim_diverter.vvp

# (Opsional) Buka waveform hasil simulasi
gtkwave tb_smart_diverter_apb.vcd
```

---

## 💻 Contoh Software Driver (C & Python)

### 1. Driver Bahasa C (Bare-Metal / FreeRTOS)
```c
#include <stdint.h>
#include <stdbool.h>

// Base address sesuai alokasi di Vivado Address Editor (misalnya 0xA0000000)
#define SLDC_BASE_ADDR        0xA0000000

#define SLDC_CTRL_REG         (*(volatile uint32_t *)(SLDC_BASE_ADDR + 0x00))
#define SLDC_STAT_REG         (*(volatile uint32_t *)(SLDC_BASE_ADDR + 0x04))
#define SLDC_THRESHOLD_REG    (*(volatile uint32_t *)(SLDC_BASE_ADDR + 0x08))
#define SLDC_SENSOR_REG       (*(volatile uint32_t *)(SLDC_BASE_ADDR + 0x0C))

#define SLDC_EN               (1 << 0)
#define SLDC_MODE_AI          (1 << 1)

// Inisialisasi IP Core dan injeksikan threshold pertama dari Edge-AI
void sldc_init(uint32_t initial_threshold) {
    SLDC_THRESHOLD_REG = initial_threshold;
    SLDC_CTRL_REG = SLDC_EN | SLDC_MODE_AI;
}

// Update threshold secara dinamis saat model AI selesai melakukan inferensi
void sldc_set_threshold(uint32_t new_threshold) {
    SLDC_THRESHOLD_REG = new_threshold;
}

// Baca telemetri untuk monitoring / dashboard
void sldc_get_status(uint32_t *live_current, bool *relay_active) {
    *live_current = SLDC_SENSOR_REG;
    *relay_active = (SLDC_STAT_REG & 0x01) ? true : false;
}

// Emergency stop untuk mematikan relai seketika
void sldc_disable(void) {
    SLDC_CTRL_REG = 0x00000000;
}
```

---

### 2. Driver Python (Linux / PYNQ / Ubuntu Kria)
```python
import mmap
import os
import struct

SLDC_BASE_ADDR = 0xA0000000
MAP_SIZE = 0x1000

class SmartLoadDiverter:
    def __init__(self, base_addr=SLDC_BASE_ADDR):
        self.f = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        self.mem = mmap.mmap(self.f, MAP_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=base_addr)

    def write_reg(self, offset, val):
        self.mem.seek(offset)
        self.mem.write(struct.pack("<I", val))

    def read_reg(self, offset):
        self.mem.seek(offset)
        return struct.unpack("<I", self.mem.read(4))[0]

    def set_ai_threshold(self, threshold_val: int):
        self.write_reg(0x08, threshold_val)
        self.write_reg(0x00, 0x03)  # Enable + Mode AI

    def get_telemetry(self):
        sensor_val = self.read_reg(0x0C)
        relay_status = self.read_reg(0x04) & 0x01
        return {"sensor_current": sensor_val, "relay_active": bool(relay_status)}

    def emergency_stop(self):
        self.write_reg(0x00, 0x00)

    def close(self):
        self.mem.close()
        os.close(self.f)

# Contoh penggunaan bersama Edge-AI inferensi:
# diverter = SmartLoadDiverter()
# diverter.set_ai_threshold(4500)
# print(diverter.get_telemetry())
```

---

## 📊 Spesifikasi Teknis

| Parameter | Spesifikasi |
| :--- | :--- |
| **Nama Modul** | `smart_diverter_axi` / `smart_diverter_apb` |
| **Lebar Bus Data** | 32-bit |
| **Lebar Bus Alamat** | 4-bit (16 Byte memory space, 4 registers) |
| **Format Data Arus** | 32-bit Unsigned Integer |
| **Latensi Komparator Hardware** | $\approx 0$ ns (Kombinasional / 1 clock cycle) |
| **Kompatibilitas FPGA** | AMD Xilinx Kria K26 SOM / KV260 / KR260, Zynq-7000, MicroBlaze, Artix/Kintex/Virtex |
| **Kompatibilitas Bus** | AMBA AXI4-Lite (ARM IHI 0022E), AMBA 3/4 APB (ARM IHI 0024C) |
| **Lisensi** | Open Custom Hardware-Software Co-Design IP Core |
