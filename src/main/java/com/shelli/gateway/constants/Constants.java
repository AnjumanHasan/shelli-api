package com.shelli.gateway.constants;

import java.io.File;
import java.nio.file.Path;
import java.util.List;
import java.util.regex.Pattern;

public class Constants {
//    public static String SYSTEM_PROMPT_PATH=  "classpath:static/SystemPrompt.md";
        public static List<Pattern> BLOCKED_PATTERNS = List.of(
            Pattern.compile("\\brm\\b"),
            Pattern.compile("\\brmdir\\b"),
            Pattern.compile("\\bdel\\b"),
            Pattern.compile("\\bmkfs\\b"),
            Pattern.compile("\\bdd\\b"),
            Pattern.compile("\\bshred\\b"),
            Pattern.compile("\\bfdisk\\b"),
            Pattern.compile("\\bformat\\b"),
            Pattern.compile("\\bkill\\s+-9\\b"),
            Pattern.compile("\\bshutdown\\b"),
            Pattern.compile("\\breboot\\b"),
            Pattern.compile("\\bchmod\\s+777\\b"),
            Pattern.compile(":\\(\\)\\s*\\{"), // fork bomb
            Pattern.compile(">\\s*/dev/"),      // writing to /dev/
            Pattern.compile("\\bmkfs\\."),       // mkfs.ext4 etc.
            Pattern.compile("\\b(sudo\\s+)?rm\\s+-rf\\b")
        );
}
