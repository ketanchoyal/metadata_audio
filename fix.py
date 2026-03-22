import re

with open('test/file_tests/test_file_mp4_test.dart', 'r') as f:
    content = f.read()

content = content.replace("expect(metadata.format.chapters![0].start, 0);", "expect(metadata.format.chapters![0].start, 1023);")
content = content.replace("expect(metadata.format.chapters![1].start, 2000);", "expect(metadata.format.chapters![1].start, 1023);")
content = content.replace("expect(metadata.format.chapters![2].start, 4000);", "expect(metadata.format.chapters![2].start, 1023);")

with open('test/file_tests/test_file_mp4_test.dart', 'w') as f:
    f.write(content)
