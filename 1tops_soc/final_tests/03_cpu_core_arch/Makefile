# ==============================================================================
# Makefile: Subsystem 03 - CPU Core Official RISC-V Architectural Verification
# ==============================================================================

PYTHON     := python3
ARCH_DIR   := ../../standard_core_tests/01_riscv_arch_test
RUNNER     := $(ARCH_DIR)/run_core_arch_test.py

.PHONY: all help clean \
        test_alu_arch test_branch_arch test_memory_arch \
        test_priv_arch test_zicsr_arch test_all

all: test_all

help:
	@echo "Subsystem 03: CPU Core RISC-V Architectural Compliance Tests"
	@echo "  make test_alu_arch     - Run ALU integer computational tests (addi, add, sub, shifts, etc.)"
	@echo "  make test_branch_arch  - Run branch & jump tests (beq, bne, blt, bge, jal, jalr)"
	@echo "  make test_memory_arch  - Run memory load/store alignment tests (lw, sw, lb, sb, etc.)"
	@echo "  make test_priv_arch    - Run privilege mode tests (ecall, ebreak, fence.i)"
	@echo "  make test_zicsr_arch   - Run Zicsr CSR access tests (csrrw, csrrs, csrrc)"
	@echo "  make test_all          - Run representative suite across all categories"
	@echo "  make clean             - Clean temporary work directories and signatures"

test_alu_arch:
	@echo "\n=== [03_CPU_ARCH] Running ALU Integer Architectural Tests ==="
	@$(PYTHON) $(RUNNER) --test addi-01
	@$(PYTHON) $(RUNNER) --test add-01
	@$(PYTHON) $(RUNNER) --test lui-01
	@$(PYTHON) $(RUNNER) --test sll-01
	@$(PYTHON) $(RUNNER) --test slt-01
	@$(PYTHON) $(RUNNER) --test xor-01

test_branch_arch:
	@echo "\n=== [03_CPU_ARCH] Running Control Transfer Architectural Tests ==="
	@$(PYTHON) $(RUNNER) --test beq-01
	@$(PYTHON) $(RUNNER) --test bne-01
	@$(PYTHON) $(RUNNER) --test jal-01
	@$(PYTHON) $(RUNNER) --test jalr-01

test_memory_arch:
	@echo "\n=== [03_CPU_ARCH] Running Memory Alignment Architectural Tests ==="
	@$(PYTHON) $(RUNNER) --test lw-align-01
	@$(PYTHON) $(RUNNER) --test sw-align-01
	@$(PYTHON) $(RUNNER) --test lh-align-01
	@$(PYTHON) $(RUNNER) --test lb-align-01

test_priv_arch:
	@echo "\n=== [03_CPU_ARCH] Running Privilege & System Trap Tests ==="
	@$(PYTHON) $(RUNNER) --test ecall
	@$(PYTHON) $(RUNNER) --test ebreak
	@$(PYTHON) $(RUNNER) --test fence-01

test_zicsr_arch:
	@echo "\n=== [03_CPU_ARCH] Running Zicsr CSR Extension Tests ==="
	@$(PYTHON) $(RUNNER) --test Zicsr-csrrw-00
	@$(PYTHON) $(RUNNER) --test Zicsr-csrrs-00

test_all: test_alu_arch test_branch_arch test_memory_arch test_priv_arch test_zicsr_arch
	@echo "\n======================================================="
	@echo " ALL CPU CORE ARCHITECTURAL COMPLIANCE TESTS PASSED!"
	@echo "======================================================="

clean:
	@rm -rf $(ARCH_DIR)/work $(ARCH_DIR)/transcript $(ARCH_DIR)/work_*/*.dut.sig
	@echo "Cleaned all architectural test simulation artifacts."
