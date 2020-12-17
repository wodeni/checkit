load("__common__.sage")


def generator():
    # Pick if yes a linear combination or no
    independent = choice([false, true])

    return {
        "independent": independent,
    }
