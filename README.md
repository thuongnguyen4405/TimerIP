# APB TIMER IP – RTL + Verification Package 

## 1. Mục tiêu dự án
Dự án này xây dựng một **Timer IP** giao tiếp qua **APB** theo đúng block diagram:
- APB Slave nhận giao dịch bus
- Register File lưu cấu hình (TCR/TDR/TCMP/THCSR)
- Counter Control tạo nhịp đếm theo chế độ default / divider
- Counter 64-bit
- Interrupt block quản lý TIER/TISR, so sánh CNT với TCMP và phát `interrupt`
- Debug/Halt mode: khi `debug_mode=1` và `halt_req=1` thì dừng counter

Ngoài “basic”, package này cũng hỗ trợ **advanced features** thường dùng trong rubric:
- Byte access (PSTRB)
- Wait-state (PREADY) cấu hình bằng parameter
- Error response (PSLVERR) cho case cấu hình div sai/không hợp lệ

## 2. Kiến trúc / Ownership rõ ràng 
<img width="1341" height="619" alt="image" src="https://github.com/user-attachments/assets/5ef81225-16f4-49cc-b721-8e34c6760e2a" />
Fig 1. Block Diagram designed by ICTC center 


## 3. Cấu trúc thư mục
```
timer_ip/
├── src/
│   ├── top_module.v         # TOP integration (connect all signals)
│   ├── apb_slave.v          # APB front-end (PREADY/PSLVERR/PSTRB)
│   ├── register.v           # Regfile (TCR/TDR/TCMP/THCSR)
│   ├── counter_control.v    # Divider + tick generation
│   ├── counter.v            # 64-bit counter + SW load + clear-on-disable
│   └── interupt.v           # Interrupt controller (TIER/TISR RW1C)
├── tb/
│   ├── apb_if.sv            # APB interface + tasks
│   └── tb_top_module.sv     # SV TB (self-checking + coverage nếu có)
├── doc/                     # để bạn bỏ PDF/spec vào
└── Makefile
```

## 4. Mô tả ngắn từng module
### `rtl/top_module.v`
- Tạo địa chỉ 32-bit từ `{BASE_ADDR20, tim_paddr[11:0]}`
- Instantiate:
  - `apb_slave` → tạo `wr_en/rd_en`, masking write theo `PSTRB`, wait-state `PREADY`
  - `register` → xuất `timer_en/div_en/div_val/halt_req`, `tcmp0/1`, tạo pulse ghi TDR
  - `counter_control` → tạo `count_tick`
  - `counter` → load counter khi SW write TDR0/TDR1; increment theo tick; clear khi timer_en H→L (advanced)
  - `interupt` → RW1C TISR, enable TIER, compare CNT==TCMP phát interrupt
- Gate tick khi halt (debug_mode & halt_req)

## 5. Build & Run (Ubuntu)
## Yêu cầu
- Ubuntu / Windows (Git Bash)
- Tối thiểu: iverilog + vvp
- Khuyến nghị: gtkwave (xem waveform)

## Chạy simulation (iverilog)

```bash
make
# hoặc
make run

### Chạy sim + coverage (Questa)
```bash
make SIM=questa cov
```

👉 tương ứng với target:
```makefile
all: run
run: $(OUT_VVP)
## Compile (không chạy)

```bash
make build

---

### 🔹 Xem waveform
```md
## Xem waveform (GTKWave)

```bash
make wave
Lưu ý: testbench phải có $dumpfile("build/wave.vcd")

---

### 🔹 Clean
```md
## Clean build

```bash
make clean

## 6. Coding style / Checklist chất lượng
- 1 owner cho 1 register (tránh race & mismatch)
- Không multi-driver trên reg
- Không combinational loop
- Giao diện APB đúng pha setup/access
- Có gating debug halt
- Có clear-on-disable (advanced)

### RESULTS

## WAVEFORM IN GTKWAVE by dumping file vcd 
-------------------------------------------COUNTER---------------------------------------------------------------------------------

-------------------------------------------APB_MASTER_SLAVE------------------------------------------------------------------------
<img width="1553" height="474" alt="image" src="https://github.com/user-attachments/assets/93a42923-1fed-42d8-b388-21769a6ce384" />

--------------------------------------------COUNTER_CONTROL-------------------------------------------------------------------------
--------------------------------------------REGISTER--------------------------------------------------------------------------------
--------------------------------------------INTERUPT--------------------------------------------------------------------------------



