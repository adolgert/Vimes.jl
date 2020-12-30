# This is another way to run Vimes.jl. It uses mutations in order to
# help select which unit tests you should run first, or at all.
# It mutates source code, runs unit tests, and records which tests pass
# or fail for which mutations. Then it makes a coverage matrix out of
# the passes and failures.
using EzXML
using Test
using TestReports


function generate_mutation_reports(tmp, cnt)
    idx = Vimes.indices(joinpath(tmp, "src"), Vimes.defaults)
    for mutation_idx in 1:cnt
        `$(Base.julia_cmd()) --project=$tmp -e 'using Pkg; Pkg.test()'`
        Vimes.mutate_and_reset(dir, tmp, idx) do
            cd(tmp) do
                ts = @testset ReportingTestSet "" begin
                    include("test/runtests.jl")
                end
                open("testlog$(mutation_idx).xml","w") do fh
                    print(fh, report(ts))
                end
            end
        end
    end
end


"""
    test_outcomes_from_xml(xmlpath)

Reads the XML from TestReports, which is a standard JUnit XML format.
The xmlpath is a document object model (DOM) from EzXML's `readxml()`.
Count each test suite as a unit test, not individual tests within
the test suite. Return a dictionary from test name to number of failures.
"""
function test_outcomes_from_xml(xmlpath)
    outcomes = Dict{String, Int}()
    for testsuite in findall("//testsuite", xmlpath)
        name = nothing
        failures = nothing
        for attrib in attributes(testsuite)
            if attrib.name == "name"
                name = attrib.content
            elseif attrib.name == "failures"
                failures = parse(Int, attrib.content)
            end
        end
        if !isnothing(name) && !isnothing(failures)
            outcomes[name] = failures
        end
    end
    outcomes
end


function read_reports(dir)
    reports = filter(x -> endswith(x, ".xml"), readdir(dir))
    sample = test_outcomes_of_xml(EzXML.readxml(joinpath(dir, first(reports))))
    outcomes = zeros(Bool, length(sample), length(reports))
    key = Dict{String, Int}((b, a) for (a, b) in enumerate(keys(sample)))

    for (report_idx, report) in enumerate(reports)
        log = EzXML.readxml(joinpath(dir, report))
        outcome = test_outcomes_of_xml(log)
        for (test_name, test_fails) in outcome
            outcomes[key[test_name], report_idx] = test_fails > 0
        end
    end
    (outcomes, key)
end


function coverage_matrix(project_dir, mutation_cnt)
    tmp = initialise_noclean(project_dir)
    generate_mutation_reports(tmp, mutation_cnt)
    coverage_matrix, test_names = read_reports(tmp)
end

function initialise_noclean(dir)
    (isfile(joinpath(dir, "Project.toml")) && isdir(joinpath(dir, "src"))) ||
      error("No Julia project found at $dir")
    tmp = joinpath(tempdir(), "vimes-$(rand(UInt64))")
    mkdir(tmp)
    for path in readdir(dir)
        if !startswith(path, ".")
            cp(joinpath(dir, path), joinpath(tmp, path))
        end
    end
    return tmp
end


"""
This is a small equivalent to TestReports.test(["BijectiveHilbert"]).
It's here because that function seems to write only one report
and won't write a second one.
"""
function runonce(tmp, logfile, pkgname)
    runtests = joinpath(tmp, "test", "runtests.jl")
    runner_code = """
using Test
using TestReports
using $(pkgname)

append!(empty!(ARGS), String[])

println("testfilename $(tmp)/test/runtests.jl")
ts = @testset ReportingTestSet "" begin
    include($(repr(runtests)))
end
 
println("Writing report to $(logfile)")
write($(repr(logfile)), report(ts))
"""
    println(runner_code)
    run(`$(Base.julia_cmd()) --project=. -e $(runner_code)`)
end

using Pkg
working = "/tmp/working"
isdir(working) || mkdir(working)
cd(working)
Pkg.activate(".")
#Pkg.add(["TestReports"])
Pkg.develop(path = expanduser("~/dev/TestReports.jl"))
using TestReports
tmp = initialise_noclean(expanduser("~/dev/BijectiveHilbert.jl"))
pkgname = "BijectiveHilbert"
Pkg.develop(path = tmp)
#Pkg.activate(tmp)
test_idx = 4
logfile = joinpath(working, "log$(test_idx).xml")
runonce(tmp, logfile, pkgname)


filter(x -> endswith(x, ".xml"), readdir(tmp))
filter(x -> endswith(x, ".xml"), readdir(working))
testlog = joinpath(tmp, "testlog.xml")
if isfile(testlog)
    cp(testlog, joinpath(working, "log$(test_idx).xml"), force = true)
    rm(testlog)
end
otherlog = joinpath(working, "$(pkgname)_testlog.xml")
isfile(otherlog) && rm(otherlog)


Pkg.rm("BijectiveHilbert")
rm(tmp, recursive=true)