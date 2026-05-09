#include "DefineParameters.h"
#include "InitializeDetail.h"
#include "Parameters.h"
#include "support/Assert.h"

namespace {

void testCompileTimeConfiguration(helix::test::Reporter& test)
{
#ifdef SINGLE
	test.expect(true, "SINGLE precision macro is enabled by default");
#else
	test.expect(false, "SINGLE precision macro is enabled by default");
#endif

#ifdef H_DIAGONAL
	test.expect(true, "H_DIAGONAL macro is enabled by default");
#else
	test.expect(false, "H_DIAGONAL macro is enabled by default");
#endif

#ifdef USE_COUNTER
	test.expect(true, "USE_COUNTER macro is enabled by default");
#else
	test.expect(false, "USE_COUNTER macro is enabled by default");
#endif
}

void testDefaultStaticParameters(helix::test::Reporter& test)
{
	test.expect(Param::N == 1024, "Param::N default is 1024");
	test.expect(Param::KMax == 2, "Param::KMax default is 2");
	test.expect(Param::JMax == 3, "Param::JMax default is 3");

	const int defaultHierarchySize = initialize_detail::hierarchySizeFor(Param::KMax + 1, Param::JMax);
	test.expect(defaultHierarchySize == 10, "default KMax/JMax hierarchy size is 10");
}

} // namespace

int main()
{
	helix::test::Reporter test;

	testCompileTimeConfiguration(test);
	testDefaultStaticParameters(test);

	return test.finish("parameter default tests");
}
