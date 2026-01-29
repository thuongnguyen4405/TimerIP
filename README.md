# APB TIMER IP – RTL + Verification Package (Professional)

## 1. Mục tiêu dự án
Dự án này xây dựng một **Timer IP** giao tiếp qua **APB** theo đúng block diagram bạn gửi:
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

## 2. Kiến trúc / Ownership rõ ràng (đúng kiểu công ty)
Để tránh double-definition và tránh bug khó debug, ownership được phân chia:
- `register.v`: **TCR, TDR0/1, TCMP0/1, THCSR**
- `interupt.v`: **TIER, TISR (RW1C), tim_int**
- `top_module.v`: mux read-data cho các vùng ownership + kết nối tất cả blocks

> Lưu ý: file `interupt.v` giữ nguyên tên theo bạn để không phá flow build cũ.

## 3. Cấu trúc thư mục
```
timer_apb_project_professional_v2/
├── rtl/
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

### Các fix chính (so với RTL ban đầu của bạn)
1) **apb_slave**: sửa hướng port, sửa read-enable, sửa masking PSTRB (tránh combinational loop), thêm BASE decode + WAIT_STATE.
2) **counter_control**: fix bug “count_en luôn 1” khi div_en=1; implement tick chuẩn `2^div_val`.
3) **counter**: fix semantics SW write TDR = load counter; bỏ kiểu snapshot lệch spec.
4) **register**: fix default TCR (timer_en=0, div_val=1), fix halt_ack RO và single-driver; thêm rule error khi đổi div fields lúc timer đang chạy.
5) **interupt**: fix TIER offset = 0x014, RW1C đúng nghĩa, chống retrigger khi counter bị halt tại đúng compare value.

## 5. Build & Run (Ubuntu)
### Yêu cầu
- Ubuntu
- Khuyến nghị: **Questa/ModelSim** để chạy coverage
- Tối thiểu: **iverilog** để compile/sim basic

### Chạy sim nhanh
```bash
make SIM=iverilog sim
```

### Chạy sim + coverage (Questa)
```bash
make SIM=questa cov
```

## 6. Coding style / Checklist chất lượng
- 1 owner cho 1 register (tránh race & mismatch)
- Không multi-driver trên reg
- Không combinational loop
- Giao diện APB đúng pha setup/access
- Có gating debug halt
- Có clear-on-disable (advanced)

## 7. Contact / Notes
Nếu bạn muốn “chuẩn rubric 100%” theo course (bao gồm check byte-access corner, wait-state exact waveforms),
mình có thể bổ sung thêm testcase/cross coverage để coverage ổn định >95%.
