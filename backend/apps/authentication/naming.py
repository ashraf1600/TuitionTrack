"""How a tutor is named to students: "Ashraf Sir" (first name, else username)."""


def sir_name(user):
    first = (getattr(user, 'first_name', '') or '').strip() or user.username
    return first if first.endswith('Sir') else f'{first} Sir'
