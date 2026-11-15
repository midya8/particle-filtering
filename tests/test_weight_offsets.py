"""Relative carried masses must survive a large common observation term."""
from decimal import Decimal as D, localcontext
import math
import random
import unittest
from particlelab import filter_particles
from particlelab.core import _weight_update


class WeightOffsets(unittest.TestCase):
    def test_constant_likelihood_keeps_weights_and_normalized_logs(self):
        prior = [math.log(.7), math.log(.2), math.log(.1)]
        for common in [-5e15, -1e24, 1e24]:
            increment, weights, logs = _weight_update(prior, [common] * 3)
            for actual, expected in zip(weights, [.7, .2, .1]):
                self.assertAlmostEqual(actual, expected, places=15)
            for actual, weight in zip(logs, weights):
                self.assertAlmostEqual(actual, math.log(weight), places=15)
            self.assertAlmostEqual(sum(map(math.exp, logs)), 1., places=15)
            self.assertTrue(math.isfinite(increment))

    def test_eighty_decimal_represented_input_references(self):
        rng = random.Random(940)
        with localcontext() as ctx:
            ctx.prec = 90
            for i in range(80):
                count = 2 + i % 7
                prior = [-rng.random()*10 for _ in range(count)]
                normalizer = math.log(math.fsum(map(math.exp, prior)))
                prior = [p-normalizer for p in prior]
                common = -float(2**(40+i%20))
                likelihood = [common+float(rng.randrange(-8, 9)) for _ in range(count)]
                increment, weights, logs = _weight_update(prior, likelihood)
                raw = [D.from_float(p)+D.from_float(l) for p,l in zip(prior, likelihood)]
                peak = max(raw)
                scaled = [(x-peak).exp() for x in raw]
                total = sum(scaled)
                for j, value in enumerate(scaled):
                    expected = value/total
                    self.assertLess(abs(weights[j]-float(expected)), 3e-15)
                    self.assertLess(abs(logs[j]-float(expected.ln())), 4e-14)
                # The large absolute evidence increment can still round away
                # small terms; bound only its floating ULP here.
                exact = peak+total.ln()
                self.assertLessEqual(abs(increment-float(exact)), 2*math.ulp(float(exact)))

    def test_bootstrap_identical_propagated_states_preserve_relative_prior(self):
        run = filter_particles([0., 10000., 0.], particles=2, seed=0, a=0.,
                               process_std=0., observation_std=1e-4,
                               initial_std=1e-4, ess_fraction=0.)
        rows = run['history']
        self.assertNotEqual(rows[0]['filtered_weights'][0], .5)
        for row in rows[1:]:
            self.assertEqual(row['filtered_particles'], [0., 0.])
            for actual, expected in zip(row['filtered_weights'], rows[0]['filtered_weights']):
                self.assertAlmostEqual(actual, expected, places=15)
            self.assertAlmostEqual(math.fsum(map(math.exp, row['filtered_log_weights'])), 1., places=15)
            self.assertFalse(row['resampled'])
        self.assertEqual(rows[2]['log_evidence_increment'], -.5*math.log(2*math.pi*1e-8))

    def test_conditional_common_likelihood_and_underflowed_mass_recovery(self):
        run = filter_particles([0., 10000., 0.], particles=3, seed=0, a=0.,
                               process_std=0., observation_std=1e-4,
                               initial_std=1e-4, ess_fraction=0., proposal='conditional')
        for row in run['history']:
            for weight in row['filtered_weights']:
                self.assertAlmostEqual(weight, 1/3, places=15)
            self.assertAlmostEqual(math.fsum(map(math.exp, row['filtered_log_weights'])), 1., places=15)
        self.assertEqual(run['history'][2]['log_evidence_increment'], -.5*math.log(2*math.pi*1e-8))
        _, weights, logs = _weight_update([0., -1000.], [0., 0.])
        self.assertEqual(weights[1], 0.)
        self.assertTrue(math.isfinite(logs[1]))
        _, weights, logs = _weight_update(logs, [-1000., 0.])
        self.assertEqual(weights, [.5, .5])
        self.assertAlmostEqual(sum(map(math.exp, logs)), 1., places=15)


if __name__ == '__main__':
    unittest.main()
