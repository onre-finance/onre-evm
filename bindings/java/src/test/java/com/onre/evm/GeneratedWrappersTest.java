package com.onre.evm;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.InputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;
import org.web3j.abi.datatypes.Event;
import org.web3j.tx.Contract;

/**
 * Checks that every event in the shipped ABI resource surfaces as a static {@link Event} on the
 * generated wrapper, so a codegen regression cannot silently drop an event.
 *
 * The ABI is scanned with a regex instead of a JSON library to keep the test classpath at what the
 * published jar already has.
 */
class GeneratedWrappersTest {

    private static final List<String> CONTRACTS = List.of("IDiamondProxy");

    private static final Pattern NAME = Pattern.compile("\"name\"\\s*:\\s*\"([A-Za-z0-9_]+)\"");

    @TestFactory
    Stream<DynamicTest> eventsHaveWrappers() throws Exception {
        String pkg = System.getProperty("bindings.package", "com.onre.evm");
        Stream.Builder<DynamicTest> tests = Stream.builder();

        for (String contract : CONTRACTS) {
            String abi = readAbi(contract);
            Class<?> wrapper = Class.forName(pkg + "." + contract);
            assertTrue(Contract.class.isAssignableFrom(wrapper), contract + " should extend web3j Contract");

            List<String> events = eventNames(abi);
            assertFalse(events.isEmpty(), contract + " ABI should declare events");

            for (String event : events) {
                tests.add(DynamicTest.dynamicTest(contract + "." + event, () -> {
                    Field field = wrapper.getField(event.toUpperCase() + "_EVENT");
                    assertTrue(Modifier.isStatic(field.getModifiers()));
                    assertEquals(Event.class, field.getType());
                    Event value = (Event) field.get(null);
                    assertEquals(event, value.getName());
                }));
            }
        }
        return tests.build();
    }

    private static String readAbi(String contract) throws Exception {
        try (InputStream in = GeneratedWrappersTest.class.getResourceAsStream("/abi/" + contract + ".json")) {
            assertNotNull(in, "abi/" + contract + ".json should be on the classpath");
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    /** Event names, in order of appearance. Each ABI entry is scanned as its own top-level object. */
    private static List<String> eventNames(String abi) {
        List<String> names = new ArrayList<>();
        for (String entry : topLevelEntries(abi)) {
            if (!entry.contains("\"type\": \"event\"") && !entry.contains("\"type\":\"event\"")) {
                continue;
            }
            // Strip nested `inputs` objects so their `name` fields are not picked up.
            String flat = entry.replaceAll("(?s)\"inputs\"\\s*:\\s*\\[.*?](?=\\s*[,}])", "\"inputs\": []");
            Matcher m = NAME.matcher(flat);
            if (m.find()) {
                names.add(m.group(1));
            }
        }
        return names;
    }

    /** Splits a JSON array of objects into its top-level object strings. */
    private static List<String> topLevelEntries(String json) {
        List<String> entries = new ArrayList<>();
        int depth = 0;
        int start = -1;
        for (int i = 0; i < json.length(); i++) {
            char c = json.charAt(i);
            if (c == '{') {
                if (depth == 0) {
                    start = i;
                }
                depth++;
            } else if (c == '}') {
                depth--;
                if (depth == 0 && start >= 0) {
                    entries.add(json.substring(start, i + 1));
                    start = -1;
                }
            }
        }
        return entries;
    }
}
