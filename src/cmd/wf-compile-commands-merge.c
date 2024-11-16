// SPDX-License-Identifier: MIT
//
// SPDX-FileContributor: Adrian "asie" Siekierka, 2023
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
	if (argc < 2) return 1;

	FILE *outf = fopen(argv[1], "wb");
	if (outf == NULL) return 1;

	if (fprintf(outf, "[") < 0) return 1;

	size_t buffersize = 32767;
	size_t infsize;
	char *buffer = malloc(buffersize + 1);
	bool buffervalid = false;

	for (int i = 2; i < argc; i++) {
		FILE *inf = fopen(argv[i], "rb");
		if (inf == NULL) continue;

		if (buffervalid) {
			if (fprintf(outf, "%s", buffer) < 0) return 1;
			buffervalid = false;
		}

		fseek(inf, 0, SEEK_END);
		infsize = ftell(inf);
		fseek(inf, 0, SEEK_SET);
		if (infsize > buffersize) {
			while (infsize > buffersize)
				buffersize = buffersize * 3 / 2;
			buffer = realloc(buffer, buffersize + 1);
		}
		buffer[infsize] = 0;
		if (fread(buffer, infsize, 1, inf) <= 0) {
			fprintf(stderr, "%s: could not read %s\n", argv[0], argv[i]);
			return 1;
		}

		fclose(inf);
		buffervalid = true;
	}

	if (buffervalid) {
		// trim final comma
		char *lastc = buffer + (infsize - 1);
		while (*lastc <= 32 || *lastc == ',') lastc--;
		lastc[1] = 0;

		if (fprintf(outf, "%s", buffer) < 0) return 1;
		buffervalid = false;
	}

	if (fprintf(outf, "]\n") < 0) return 1;
	fclose(outf);

	return 0;
}

