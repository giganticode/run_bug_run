package run_bug_run;

import org.jruby.*;
import org.jruby.javasupport.JavaEmbedUtils;
import org.jruby.runtime.builtin.IRubyObject;

import java.util.ArrayList;
import java.util.Arrays;
import java.io.IOException;
import java.net.URISyntaxException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.charset.StandardCharsets;

public class SubmissionOutputMatcher {

    public static SubmissionOutputMatcher INSTANCE = createInstance();

    public static boolean isMatch(String expectedOutput, String actualOutput, String problemId) {
        return INSTANCE.match(expectedOutput, actualOutput, problemId);
    }

    public static SubmissionOutputMatcher createInstance() {
        try {
            return new SubmissionOutputMatcher();
        } catch(IOException|URISyntaxException e) {
            return null;
        }
    }

    private Ruby runtime;
    private RubyRuntimeAdapter evaler;

    public SubmissionOutputMatcher() throws IOException, URISyntaxException {
        this.runtime = JavaEmbedUtils.initialize(Arrays.asList());
        // this.runtime = JavaEmbedUtils.initialize(Arrays.asList("submission_output_matcher.rb"));
        this.evaler = JavaEmbedUtils.newRuntimeAdapter();

        byte[] codeBytes = Files.readAllBytes(Paths.get(getClass().getResource("/submission_output_matcher.rb").toURI()));
        String code = new String(codeBytes, StandardCharsets.UTF_8);
        this.evaler.eval(this.runtime, code);
    }

    public boolean match(String expectedOutput, String actualOutput, String problemId) {
        IRubyObject rubyClass = this.evaler.eval(this.runtime, "RunBugRun::SubmissionOutputMatcher");
        Object[] parameters = {
            RubyString.newUTF8String(this.runtime, expectedOutput),
            RubyString.newUTF8String(this.runtime, actualOutput),
            RubyString.newUTF8String(this.runtime, problemId)
        };
        Boolean result = (Boolean) JavaEmbedUtils.invokeMethod(this.runtime, rubyClass, "match?", parameters, Boolean.class);
        return result;
    }

    public static void main(String args[]) {
        System.out.println(isMatch(args[0], args[1], args[2]));
    }
}