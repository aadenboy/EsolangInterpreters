#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>

// NOTE: boilerplate necessary to emulate Iterate I/O specifications

bool usefile = false;
bool doneinput = false;
FILE *infile = NULL;
char *input;
char buffer;

// https://stackoverflow.com/q/73240276
void prompt() { // arbitrary length
    doneinput = false;
    free(input);
    input = malloc(1);
    char c;
    char *reinput;
    size_t len = 0;
    size_t buf = 1;
    while ((c = getchar()) != '\n' && c != EOF) {
        if (len + 1 >= buf) {
            buf *= 2;
            reinput = realloc(input, buf);
            if (reinput == NULL) exit(1);
            input = reinput;
        }
        input[len++] = c;
    }
    input[len] = '\0';
}
char pop() {
    if (usefile && doneinput) return '\0';
    if (usefile) {
        char out = fgetc(infile);
        if (out == EOF) {
            doneinput = true;
            return '\0';
        } else return out;
    } else {
        if (input[0] == '\0' && doneinput) prompt();
        else if (input[0] == '\0') { doneinput = true; return '\0'; }
        //if (input[0] == '\0') return '\0';
        char out = input[0];
        buffer = out;
        memmove(input, input + 1, strlen(input) + 1);
        return out;
    }
}
void unpop() {
    if (usefile) fseek(infile, -1, SEEK_CUR);
    else {
        if (buffer == '\0') return;
        memmove(input + 1, input, strlen(input) + 1);
        input[0] = buffer;
        buffer = '\0';
    }
}

uint64_t readnum() {
    uint64_t num = 0;
    if (usefile && doneinput) return 0;
    bool foundnum = false;
    while (true) {
        char c = pop();
        if (c == '\0') return num;
        if (c >= '0' && c <= '9') {
            num = num * 10 + c - '0';
            foundnum = true;
        } else if (foundnum) {
            unpop();
            return num;
        }
    }
}
uint64_t readutf8() {
    if (usefile && doneinput) return '\0';
    char initial = pop();
    int bytes = 0;
    if (initial >> 6 == 0x2) return '\0'; // invalid utf-8
    else if (initial < 0x80) return initial;
    else if (initial < 0xE0) bytes = 1;
    else if (initial < 0xF0) bytes = 2;
    else if (initial < 0xF8) bytes = 3;
    uint64_t num = initial & ((1 << (7 - bytes)) - 1);
    bool valid = true;
    for (int i = 0; i < bytes; i++) {
        char c = pop();
        if (c >> 6 != 0x2) valid = false; // invalid utf-8
        num = (num << 6) | (c & 0x3F);
    }
    if (!valid) return 0;
    return num;
}
void oututf8(uint64_t num) {
    if (num < 0x80) {
        putchar(num);
        return;
    };
    char suffix = num & 0x3F;
    char c4 = 0x80 | suffix;
    num >>= 6;
    if (num < 0x20) {
        putchar(0xC0 + num);
        putchar(c4);
        return;
    };
    suffix = num & 0x3F;
    char c3 = 0x80 | suffix;
    num >>= 6;
    if (num < 0x10) {
        putchar(0xE0 + num);
        putchar(c3);
        putchar(c4);
        return;
    }
    suffix = num & 0x3F;
    char c2 = 0x80 | suffix;
    num >>= 6;
    putchar(0xF0 + num);
    putchar(c2);
    putchar(c3);
    putchar(c4);
}

//$PROGRAM$//

int main(void) {
    input = malloc(1);
    input[0] = '\0';
    if (!usefile) doneinput = true;
    iterateprogram();
    free(input);
    return 0;
}
