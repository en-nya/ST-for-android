#include <cstdio>
#include <string>
int main(int argc, char** argv) {
    std::string s = "\xc3\xa1z";           // needs ICU for normalize in real Node, here just C++
    printf("PROBE_OK argc=%d cxx=%d\n", argc, (int)s.size());
    return 0;
}
