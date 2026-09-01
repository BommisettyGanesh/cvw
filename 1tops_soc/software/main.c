typedef unsigned char uint8_t;
typedef unsigned int uint32_t;

// Multiplier Base Address
#define MULT_BASE 0x30000000
#define MULT_OPA  *((volatile uint32_t*)(MULT_BASE + 0x00))
#define MULT_OPB  *((volatile uint32_t*)(MULT_BASE + 0x04))
#define MULT_RES  *((volatile uint32_t*)(MULT_BASE + 0x08))
#define MULT_PRINT *((volatile uint32_t*)(MULT_BASE + 0x0C))
#define PRINT_CHAR(c) do { MULT_PRINT = (c); for(volatile int i=0; i<10; i++); } while(0)

void print_testing() {
    PRINT_CHAR('T'); PRINT_CHAR('e'); PRINT_CHAR('s'); PRINT_CHAR('t');
    PRINT_CHAR('i'); PRINT_CHAR('n'); PRINT_CHAR('g'); PRINT_CHAR(' ');
    PRINT_CHAR('A'); PRINT_CHAR('H'); PRINT_CHAR('B'); PRINT_CHAR(' ');
    PRINT_CHAR('M'); PRINT_CHAR('u'); PRINT_CHAR('l'); PRINT_CHAR('t');
    PRINT_CHAR('i'); PRINT_CHAR('p'); PRINT_CHAR('l'); PRINT_CHAR('i');
    PRINT_CHAR('e'); PRINT_CHAR('r'); PRINT_CHAR('.'); PRINT_CHAR('.');
    PRINT_CHAR('.'); PRINT_CHAR('\n');
}

void print_result_prefix() {
    PRINT_CHAR('R'); PRINT_CHAR('e'); PRINT_CHAR('s'); PRINT_CHAR('u');
    PRINT_CHAR('l'); PRINT_CHAR('t'); PRINT_CHAR(' '); PRINT_CHAR('i');
    PRINT_CHAR('s'); PRINT_CHAR(':'); PRINT_CHAR('\n');
}

void print_passed() {
    PRINT_CHAR('T'); PRINT_CHAR('e'); PRINT_CHAR('s'); PRINT_CHAR('t');
    PRINT_CHAR(' '); PRINT_CHAR('P'); PRINT_CHAR('A'); PRINT_CHAR('S');
    PRINT_CHAR('S'); PRINT_CHAR('E'); PRINT_CHAR('D'); PRINT_CHAR('!');
    PRINT_CHAR('\n');
}

void print_failed() {
    PRINT_CHAR('T'); PRINT_CHAR('e'); PRINT_CHAR('s'); PRINT_CHAR('t');
    PRINT_CHAR(' '); PRINT_CHAR('F'); PRINT_CHAR('A'); PRINT_CHAR('I');
    PRINT_CHAR('L'); PRINT_CHAR('E'); PRINT_CHAR('D'); PRINT_CHAR('!');
    PRINT_CHAR('\n');
}

void print_hex(uint32_t val) {
    PRINT_CHAR('0'); PRINT_CHAR('x');
    for (int i = 28; i >= 0; i -= 4) {
        uint8_t digit = (val >> i) & 0xF;
        if (digit < 10) {
            PRINT_CHAR('0' + digit);
        } else {
            PRINT_CHAR('A' + (digit - 10));
        }
    }
    PRINT_CHAR('\n');
}

int main() {
    print_testing();

    MULT_OPA = 0002;
    MULT_OPB = 0001;

    uint32_t res = MULT_RES;

    print_result_prefix();
    print_hex(res);

    if (res == (0001 * 0002)) {
        print_passed();
    } else {
        print_failed();
    }

    // Done
    while(1);
    return 0;
}
